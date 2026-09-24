# Chainlink CRE Automation

The automation layer is a scheduling boundary around the protocol, not a privileged component inside it.
Everything it does, a human could do with a transaction; its value is that it happens reliably, on a
schedule, without a privileged key.

Related: [contracts.md](contracts.md#protocolautomationreceiver) (receiver reference),
[`cre/protocol-automation/README.md`](../cre/protocol-automation/README.md) (workflow internals and
partitioning), [security.md](security.md#2-adversarial-capabilities-considered) (attacker model).

---

## 1. Scope

Core protocol contracts are **Chainlink-agnostic**. They expose bounded view functions for discovery and
ordinary lifecycle functions for execution. The automation layer adds:

```text
Cron trigger
   ↓
CRE workflow (TypeScript)
   ↓
Bounded on-chain discovery (registry + domain views)
   ↓
Signed action report
   ↓
KeystoneForwarder
   ↓
ProtocolAutomationReceiver   ← the trusted on-chain boundary
   ↓
Protocol domain function     ← the source of truth
```

Nothing in `src/core/**` imports anything from `src/automation/**`. This is enforced by design rule 7 in
[architecture.md](architecture.md), and it is why replacing or upgrading the automation layer never
requires touching the protocol contracts.

## 2. Automated actions

| Domain | Action | Automated function |
| --- | --- | --- |
| Open Auction | 0 `FINALIZE_OPEN_AUCTION` | `OpenAuction.finalizeAuction(uint256)` |
| Blind Auction | 1 `FINALIZE_BLIND_AUCTION` | `BlindAuction.finalizeAuction()` |
| Dutch Auction | 2 `EXPIRE_DUTCH_AUCTION` | `DutchAuction.expireAuction(uint256)` |
| Marketplace | 3 `EXPIRE_OFFER` | `Marketplace.expireOffer(uint256)` |
| Raffle | 4 `REQUEST_RAFFLE_WINNER` | `Raffle.requestRandomWinner(uint256)` |
| Raffle | 5 `PROCESS_RAFFLE_REFUNDS` | `Raffle.processRaffleRefunds(uint256,uint256)` |
| Raffle | 6 `FINALIZE_FAILED_RAFFLE` | `Raffle.finalizeFailedRaffle(uint256)` |

`Raffle.retryRandomWinnerRequest(uint256)` is **intentionally excluded**. It is `onlyOwner` privileged
recovery, and putting a privileged call on a scheduled path would make the automation layer a standing
privilege rather than a convenience. Recovery stays a deliberate human action.

## 3. On-chain boundary

`ProtocolAutomationReceiver` is built on Chainlink's official `ReceiverTemplate` (vendored under
`src/automation/chainlink/`). It starts **paused** and rejects every report until both a workflow id and a
workflow author are configured.

A report is accepted only if all of the following hold:

| Check | Rejected with |
| --- | --- |
| Receiver is not paused | `AutomationPaused` |
| Caller is the configured forwarder, and that forwarder is non-zero | `InvalidForwarder` |
| Workflow id **and** author are configured | `WorkflowNotConfigured` |
| Report is exactly 224 bytes | `InvalidReport` |
| Action index is within the enum | `InvalidAction` |
| Target instance is non-zero and has code | `InvalidInstance` |
| Chain selector matches the one fixed at construction | `InvalidChainSelector` |
| `scheduledAt` is non-zero and at most 10 minutes in the future | `InvalidSchedule` |
| Registry record exists and is active | `InactiveInstance` |
| Registry kind matches the action's expected kind | `InvalidTargetKind` |
| Refund batch: `id != 0`, `1 <= value <= 100`, cursor matches on-chain `refundCursor` | `InvalidActionId`, `InvalidRefundBatch`, `InvalidRefundCursor` |
| Other actions: `id != 0` (except blind), `value == 0`, `cursor == 0` | `InvalidActionId`, `InvalidActionValue` |
| Replay key `keccak256(action, instance, id, value, cursor)` is unseen | `ReplayOrStaleReport` |

The report envelope additionally carries `workflowId | name(10) | owner(20) | reportId(2)`, which the
forwarder authenticates and the template checks against the configured identity.

**There is no `target.call(data)` anywhere in the receiver.** The action set is an explicit
if/else allowlist. Adding an action requires editing both `_processReport` and `_validate`, which is the
intended friction.

## 4. Discovery model

The workflow performs **one registry call per protocol kind** and **one domain discovery call per selected
instance**. Domain discovery is bounded by *iterations*, not only by result count:

```solidity
automationDueIds(cycle, maxScan, maxItems)
automationDueOfferIds(cycle, maxScan, maxItems)
automationCandidates(cycle, maxScan, maxItems)
```

| Parameter | Meaning | On-chain hard cap |
| --- | --- | --- |
| `maxScan` | How many ids this single call may inspect | `AutomationScanLib.MAX_SCAN = 500` |
| `maxItems` | How many ids this single call may return | `AutomationScanLib.MAX_ITEMS = 100` |
| `cycle` | Which window of the id space to inspect | — |

`AutomationScanLib.window(total, cycle, maxScan)` computes a window of at most `maxScan` ids and rotates it
by `cycle`; `capacity` clamps the result count. The default configuration selects **one instance per kind
per execution**.

> **Do not** replace the candidate helpers with an unbounded per-id scan. The bounded window is what makes
> the read cost predictable, and predictability is the entire reason the gas and read budgets hold.

### Read budget

```text
receiver.paused()                                    1 read
registry.automationInstancesWithCycle × 5 kinds      5 reads
domain discovery on the selected instance            1 read
                                                     -------
                                                     11 reads
```

**11 EVM reads per execution**, against a documented quota of 15. Simulate with the CLI `--limits` option
before deploying to confirm the quotas on the target network.

### Rotation and partitioning

Instance selection is `slot * partitionCount + partitionIndex`, where `slot = scheduledAt / 60`. With one
partition and 250 instances of a kind, every instance is visited once per 250 minutes. Deploying
`partitionCount = N` means deploying **N workflow clones**, each with its own config file
(`partitionIndex` 0..N-1) and its own `workflow-name`; each clone visits a different registry position each
minute, so an instance is visited every `ceil(count / N)` minutes (250 instances, 25 partitions: every 10
minutes).

Keep `partitionCount <=` the number of instances of the smallest kind. Otherwise two partitions can select
the same instance in the same minute; the second identical report reverts and is logged as a failed write —
harmless, but noisy.

## 5. Simulation vs. production receivers

`cre workflow simulate` delivers reports through a `MockForwarder` that provides **no workflow metadata**,
so workflow id/author validation must be off. Rather than weakening the production receiver, the repository
deploys a separate one.

| Target | Receiver | Forwarder | Workflow id / author |
| --- | --- | --- | --- |
| `simulation-settings` (`config.simulation.json`) | `ProtocolAutomationSimulationReceiver` (`DeployAutomationSimulationReceiver.s.sol`, testnets only) | chain's MockForwarder | must stay unset |
| `staging-settings` (real testnet run) | `ProtocolAutomationReceiver` | real KeystoneForwarder | required |
| `production-settings` | `ProtocolAutomationReceiver` | real KeystoneForwarder | required |

Never call `setExpectedWorkflowId` / `setExpectedAuthor` on the simulation receiver, and never use the
simulation receiver outside simulation. The receiver **can never be unpaused** without both values, and
rejects reports if either is later cleared.

## 6. Gas budget

`gasLimit = 1,000,000` and `refundBatchSize = 12` are backed by
`test/automation/ProtocolAutomationGas.t.sol`, measured on the real contracts from cold storage:

| Operation | Measured cost |
| --- | --- |
| Finalize / expire / request actions | ~180k–360k gas |
| Refund batch of 12 entries | ~510k gas |
| Refund batch of 100 entries | ~3.1M gas — **does not fit** |

If you raise `refundBatchSize` or lower `gasLimit`, update the constants in that test and re-run it. The
test is the source of truth for both numbers; the documentation follows it, not the other way around.

`requestRandomWinner` was measured against the VRF mock. Re-measure it on testnet against the real
coordinator before production.

## 7. Deployment order

1. Deploy and verify the core protocol ([deployment.md](deployment.md)).
2. **Simulation:** deploy `ProtocolAutomationSimulationReceiver` with the MockForwarder, run
   `cre workflow simulate --target simulation-settings` (add `--limits` to check quotas).
   **Real runs:** deploy `ProtocolAutomationReceiver` with the target-chain Chainlink Keystone Forwarder
   and the protocol registry address.
3. Deploy the CRE workflow; record its workflow id and author.
4. Call `ConfigureAutomationReceiver.s.sol` with those values. The script sets the workflow identity and
   unpauses the receiver.
5. Simulate the workflow.
6. Exercise the full write path on testnet: CRE report → forwarder → receiver → domain function.
7. Run the final Foundry suite and deployment verification before mainnet activation.

Requires `make setup` for the Solidity dependencies and `npm ci` for the workflow dependencies. The package
lockfile is committed; `npm ci` fails if it drifts.

## 8. Pointers

| Topic | Where |
| --- | --- |
| Workflow internals, read budget arithmetic, latency, partitioning guidance | [`cre/protocol-automation/README.md`](../cre/protocol-automation/README.md) |
| Receiver contract reference and validation order | [contracts.md](contracts.md#protocolautomationreceiver) |
| Attacker model for reports and replay | [security.md](security.md#2-adversarial-capabilities-considered) |
| Workflow source | `cre/protocol-automation/{main,automation,report,config}.ts` |
| On-chain tests | `test/automation/` |

## 9. Operational warnings

- **Do not put private RPC URLs, private keys, workflow secrets, or mainnet addresses in source control.**
- A silently failing automation layer is invisible until users notice stuck auctions or expiring offers.
  Monitor `AutomationActionExecuted` along with execution failures.
- If the workflow is paused or the receiver is paused, every automated action stops. Both states are
  intentional and reversible, but neither is self-healing.
- `PROCESS_RAFFLE_REFUNDS` relies on the on-chain refund cursor. Never submit a batch with a hand-written
  cursor; read `refundCursor(raffleId)` immediately before submitting.

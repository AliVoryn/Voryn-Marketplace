# Ali Voryn Protocol Automation (Chainlink CRE)

## What this workflow automates

- OpenAuction `finalizeAuction(uint256)`
- BlindAuction `finalizeAuction()`
- DutchAuction `expireAuction(uint256)`
- Marketplace `expireOffer(uint256)`
- Raffle `requestRandomWinner(uint256)`
- Raffle `processRaffleRefunds(uint256,uint256)`
- Raffle `finalizeFailedRaffle(uint256)`

## Runtime architecture

`Cron trigger -> CRE workflow -> finalized-chain reads -> signed report -> KeystoneForwarder -> ProtocolAutomationReceiver -> domain function`.

The core contracts remain Chainlink-agnostic. The receiver is built on Chainlink's official `ReceiverTemplate` and is fail-closed until a real CRE workflow id and workflow author are configured.

## Read budget

The workflow handles **one protocol instance per kind per execution** (`instancesPerKindPerRun` is fixed to 1). One execution performs one receiver `paused()` read, five registry reads (`automationInstancesWithCycle`, one per kind) and five domain reads (one per selected instance): 11 EVM reads before writes, below the documented 15 EVM-read-per-execution quota. Simulate with the CLI `--limits` option before deploying.

Protocol kinds are visited in a rotating order (start kind = minute slot modulo 5), so no kind is starved when earlier kinds fill `maxReportsPerRun`.

## Bounded discovery

Domain discovery views (`automationDueIds`, `automationDueOfferIds`, `automationCandidates`) take `(cycle, maxScan, maxItems)`. `maxItems` only caps the number of returned ids; `maxScan` caps the **iterations**. One call inspects a single window of at most `maxScan` ids (hard on-chain cap `AutomationScanLib.MAX_SCAN` = 500, whatever the caller passes). The window is `cycle % ceil(total / maxScan)`, and `cycle` is the number of complete passes over the registry set returned by `ProtocolRegistry.automationInstancesWithCycle`, so it grows by exactly one between two visits of the same instance and every id is covered. With `maxScan = 250` an instance holding 1,000,000 ids is fully covered after 4,000 visits of that instance; a due id therefore waits at most `visitInterval * windows`. If an instance can reach that scale, shorten `visitInterval` with partitions (below).

## Rotation and partitions

Each minute the registry offset is `slot * partitionCount + partitionIndex` (`slot = scheduledAt / 60`). With one partition and 250 instances of a kind, every instance is visited once per 250 minutes. With `partitionCount = N` you deploy **N clones of this workflow**, each with its own config file (`partitionIndex` 0..N-1) and its own `workflow-name`; every clone visits a different registry position each minute, so an instance is visited every `ceil(count / N)` minutes (250 instances, 25 partitions: every 10 minutes). Keep `partitionCount` <= the number of instances of the smallest kind, otherwise two partitions can pick the same instance in the same minute (the second identical report just reverts and is logged as a failed write).

## Gas limits

`gasLimit` (1,000,000) and `refundBatchSize` (12) were measured on the real contracts from cold storage (`forge test --match-path test/automation/ProtocolAutomationGas.t.sol -vv`): finalize/expire/request actions use roughly 180k-360k gas, a 12-entry refund batch about 510k, while a 100-entry refund batch needs about 3.1M and would run out of gas. If you raise `refundBatchSize` or lower `gasLimit`, update the constants in that test and re-run it. `requestRandomWinner` was measured against the VRF mock; re-measure on testnet with the real coordinator.

## Simulation vs. real receivers

`cre workflow simulate` delivers reports through a `MockForwarder` that provides no workflow metadata, so workflow id / author validation must be off. Use two different receivers:

| Target | Receiver | Forwarder | Workflow id / author |
|---|---|---|---|
| `simulation-settings` (`config.simulation.json`) | `ProtocolAutomationSimulationReceiver` (`DeployAutomationSimulationReceiver.s.sol`, testnets only) | chain's MockForwarder | must stay unset |
| `staging-settings` (real testnet run) | `ProtocolAutomationReceiver` | real KeystoneForwarder | required |
| `production-settings` | `ProtocolAutomationReceiver` | real KeystoneForwarder | required |

Never call `setExpectedWorkflowId` / `setExpectedAuthor` on the simulation receiver, and never use the simulation receiver outside simulation.

## Deployment requirements

1. Install the Solidity dependencies with `make setup` and the workflow dependencies with `npm ci` in this directory.
2. Simulation first: deploy `ProtocolAutomationSimulationReceiver` with the MockForwarder, put it in `config.simulation.json`, run `cre workflow simulate --target simulation-settings`.
2b. Real runs: deploy `ProtocolAutomationReceiver` with the **real target-chain Keystone Forwarder** and `ProtocolRegistry` address.
3. Deploy the CRE workflow and obtain the workflow id and workflow author.
4. Set those values through `ConfigureAutomationReceiver.s.sol` (uses the template setters `setExpectedWorkflowId` / `setExpectedAuthor`); this also unpauses the receiver.
5. Run the TypeScript tests (`npm test`).
6. Execute one end-to-end testnet run before mainnet.
7. The package lockfile is committed; keep it in sync (`npm ci` fails otherwise).

The current TypeScript SDK version in this project is pinned to `@chainlink/cre-sdk` `1.22.0`. The CRE CLI should be installed at the version required by the current official documentation (currently 1.32.0).

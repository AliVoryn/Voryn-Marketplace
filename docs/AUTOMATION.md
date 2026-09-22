# Chainlink CRE Automation

## Scope

This integration keeps the core protocol contracts Chainlink-agnostic. CRE is responsible for scheduling/discovery and on-chain reporting; `ProtocolAutomationReceiver` is the trusted on-chain boundary; existing protocol lifecycle functions remain the source of truth.

Automated actions:

- `OpenAuction.finalizeAuction(uint256)`
- `BlindAuction.finalizeAuction()`
- `DutchAuction.expireAuction(uint256)`
- `Marketplace.expireOffer(uint256)`
- `Raffle.requestRandomWinner(uint256)`
- `Raffle.processRaffleRefunds(uint256,uint256)`
- `Raffle.finalizeFailedRaffle(uint256)`

`Raffle.retryRandomWinnerRequest(uint256)` is intentionally left as privileged recovery (`onlyOwner`) and is not part of the trust-minimized automation path.

## On-chain boundary

`ProtocolAutomationReceiver` starts paused and rejects reports until both a workflow id and workflow author are configured. `ProtocolAutomationReceiver` is built on Chainlink's official `ReceiverTemplate` (vendored in `src/automation/chainlink/`): reports are accepted only from the configured Chainlink forwarder and must carry the expected workflow id and author metadata (`workflowId | name(10) | owner(20) | reportId(2)`). Reports must target an active registry instance of the expected kind, and must use the configured chain selector. Refund batches additionally carry the expected on-chain cursor.

The receiver has an explicit action allowlist. It does not expose arbitrary `target.call(data)`.

## CRE discovery design

The workflow uses one registry call per protocol kind (`automationInstancesWithCycle`) and one domain discovery call per selected instance. Domain discovery is bounded by **iterations**, not only by result count: each call takes `(cycle, maxScan, maxItems)` and inspects one window of at most `maxScan` ids (on-chain hard cap 500). `cycle` rotates the window across all ids. The default configuration selects one instance per kind per execution (11 EVM reads, below the 15-read quota).

Instance rotation is `slot * partitionCount + partitionIndex`. For many instances deploy `partitionCount` workflow clones (one `partitionIndex` each). See `cre/protocol-automation/README.md` for latency numbers. Do not replace the candidate helpers with an unbounded per-ID scan.

## Simulation vs. production receiver

`cre workflow simulate` uses a `MockForwarder` without workflow metadata, so it needs `ProtocolAutomationSimulationReceiver` (testnets only, workflow identity must stay unset). The real testnet run and production use `ProtocolAutomationReceiver` with the real KeystoneForwarder and a configured workflow id + author. The production receiver can never be unpaused without both values and rejects reports if either is later cleared.

## Gas

`gasLimit = 1,000,000` and `refundBatchSize = 12` are backed by `test/automation/ProtocolAutomationGas.t.sol`. `processRaffleRefunds` with 100 entries needs ~3.1M gas and does not fit.

## Deployment order

1. Deploy and verify the core protocol.
2. Simulation: deploy `ProtocolAutomationSimulationReceiver` (MockForwarder), run `cre workflow simulate --target simulation-settings` (add `--limits` to check quotas). Real runs: deploy `ProtocolAutomationReceiver` with the target-chain Chainlink Keystone Forwarder and the protocol registry.
3. Deploy the CRE workflow and record its workflow id and author.
4. Call `ConfigureAutomationReceiver.s.sol` with those identity values. The script sets the workflow identity and unpauses the receiver.
5. Simulate the workflow.
6. Exercise the full write path on testnet: CRE report -> forwarder -> receiver -> domain function.
7. Run the final Foundry suite and deployment verification before mainnet activation.

Do not put private RPC URLs, private keys, workflow secrets or mainnet addresses in source control.

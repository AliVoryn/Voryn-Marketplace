# Coverage Baseline

Measured with `forge coverage --report summary --no-match-path 'script/**'` (Foundry 1.8.3, solc 0.8.24, default profile), restricted to `src/`.

```text
Lines:       98.04% (1898/1936)
Statements:  96.48% (2468/2558)
Branches:    88.78% (435/490)
Functions:   98.46% (319/324)
```

The `Total` row printed by forge is lower (about 86.7% lines) because it also counts test helpers and mocks.

## Branch coverage of the sensitive contracts

| Contract | Branches |
|---|---|
| Marketplace | 95.45% (63/66) |
| ProtocolFactory | 93.75% (30/32) |
| CustomNFT | 93.33% (28/30) |
| ProtocolRegistry | 92.31% (12/13) |
| Treasury | 91.67% (22/24) |
| OpenAuction | 88.89% (48/54) |
| Raffle | 88.71% (55/62) |
| DutchAuction | 88.57% (31/35) |
| ProtocolAutomationReceiver | 88.00% (44/50) |
| BlindAuction | 81.58% (31/38) |
| Staking | 78.26% (36/46) |
| PaymentManager and all libraries | 100% |

`src/automation/chainlink/ReceiverTemplate.sol` is Chainlink's official template, vendored; its owner-only setters are exercised only where the receiver uses them.

## History

| Date | Tests | Lines | Statements | Branches | Functions |
|---|---|---|---|---|---|
| 2026-09-19 (first supplied baseline) | 357 | 83.69% | 78.67% | 67.45% | 89.11% |
| current | 649 (648 passed, 1 skipped) | 98.04% | 96.48% | 88.78% | 98.46% |

## Interpretation

Coverage is a diagnostic signal. Uncovered branches must be reviewed for whether the path is reachable, intentionally defensive (for example the escrow-invariant reverts and the `vrfRequestId` mismatch guard in `rawFulfillRandomWords`), or actually missing a test. The lowest branch coverage is in Staking and BlindAuction and is the next place to add tests.

Deployment scripts are excluded from application coverage; their behaviour is verified by the deployment, preflight, verification and script tests.

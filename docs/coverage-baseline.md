# Coverage Baseline

> **Status: recorded baseline, not a live measurement.** The numbers below were produced by a real
> `forge coverage` run on an earlier revision of this repository and are retained so that a future run can
> be compared against them. Re-measure before quoting them as current.

## Reproduction command

```bash
forge coverage --report summary --no-match-path 'script/**'
```

Environment for the recorded run: Foundry **1.8.3**, solc **0.8.24**, `default` profile
(`fuzz.runs = 512`, `invariant.runs = 128`, `invariant.depth = 128`), restricted to `src/`.

## Application coverage

```text
Lines:       98.04% (1898/1936)
Statements:  96.48% (2468/2558)
Branches:    88.78% (435/490)
Functions:   98.46% (319/324)
```

The `Total` row that `forge` prints is lower — roughly **86.7% lines** — because it also counts test
helpers and mocks that exist only to support the suites. Application coverage is the number that matters
and is why the command is scoped to `src/`.

## Branch coverage of the sensitive contracts

| Contract | Branches |
| --- | --- |
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

`src/automation/chainlink/ReceiverTemplate.sol` is Chainlink's official template, vendored verbatim. Its
owner-only setters are exercised only where the receiver actually uses them, which is why the vendored file
itself is treated as out of scope for application coverage.

## History

| Point in time | Test functions counted by forge | Lines | Statements | Branches | Functions |
| --- | --- | --- | --- | --- | --- |
| First supplied baseline | 357 | 83.69% | 78.67% | 67.45% | 89.11% |
| Recorded baseline | 649 (648 passed, 1 skipped) | 98.04% | 96.48% | 88.78% | 98.46% |

The first row is the state of the tree before the verification work that produced this documentation set.
The improvement is concentrated in exactly the places the invariants were added: escrow accounting in the
auctions and the raffle, and liability accounting in the two ledgers.

### Why the test count here differs from the static count

[test-strategy.md](test-strategy.md) reports **638 test functions + 14 invariant functions** from a static
count of the source tree. `forge test` counts differently: it reports one entry per test function **per
test contract that can run it**, so inherited helpers and shared bases can appear more than once in its
summary. A static count and a forge count will never match exactly, and neither is wrong — they answer
different questions. Use the static count to size the tree, and a forge run to know what passed.

## Interpretation

Coverage is a diagnostic signal. It tells you where to look, not whether a contract is correct.

The rule applied when reading uncovered branches is: **classify before adding a test.**

| Classification | Action |
| --- | --- |
| Reachable and meaningful | Add a test |
| Unreachable because of a compile-time guarantee | Document it; no test |
| Intentionally defensive (an invariant guard that should never fire) | Document it; no test, because a test that triggers it would be testing a broken state |
| Reachable only through an admin configuration that is itself tested | Accept, and note the configuration |

Known intentionally-defensive paths include the escrow-invariant reverts in `OpenAuction`,
`BlindAuction`, `Raffle`, and `Marketplace`, and the `vrfRequestId` mismatch guard in
`rawFulfillRandomWords`. These exist to make a broken state impossible rather than to be exercised by a
passing test.

Where to look next, in priority order:

1. **Staking** (78.26% branches) — reward-program branching and the emergency paths are the thinnest area.
2. **BlindAuction** (81.58% branches) — reveal-extension and cancellation combinations.
3. Everything above 88% — treat any new uncovered branch as a change to be justified, not as noise.

## Exclusions

| Excluded | Reason |
| --- | --- |
| `script/**` | Deployment scripts are verified by the deployment, preflight, verification, and script tests rather than by application coverage |
| `src/automation/chainlink/**` | Vendored Chainlink template |
| `test/**`, `lib/**` | Not application code |
| Vendored `lib/chainlink/**` | Unused tree; nothing in `src/` or `test/` imports it (the remapping `@chainlink/` resolves to `lib/chainlink-evm/`) |

## Comparing a future run

When you re-measure, record all four numbers plus the exact toolchain, because the two are meaningless
apart:

```text
Foundry:    <forge --version output>
Profile:    default | ci | ci-fast
Lines:      xx.xx% (n/m)
Statements: xx.xx% (n/m)
Branches:   xx.xx% (n/m)
Functions:  xx.xx% (n/m)
```

A coverage drop is not automatically a defect and a coverage rise is not automatically an improvement.
Both require the classification pass above.

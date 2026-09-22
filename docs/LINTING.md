# Linting

`forge lint` runs in CI and exits 0. Its scope is set in `foundry.toml`:

- `test/**`, `script/**` and `src/automation/chainlink/**` (Chainlink's vendored template) are not linted.
- `block-timestamp` is excluded: auctions, offers, raffles, staking schedules and the automation receiver depend on block time by design.

## Remaining findings in `src/`

The remaining findings are heuristic static-analysis output. They are kept visible on purpose. They have not been individually adjudicated and are not a security assessment: each one belongs on the checklist of the independent security review.

| Rule | Count | Meaning |
|---|---|---|
| `reentrancy-events` | 76 | An event is emitted after an external call. |
| `reentrancy-no-eth` | 33 | State is written after an external call. |
| `reentrancy-eth` | 13 | State is written after an external call that can transfer ETH. Every flagged function carries `nonReentrant`. |
| `unsafe-typecast` | 21 | A down-cast that is not checked by a `SafeCast` call. |
| `uninitialized-local` | 11 | A local declared without an initial value (counters start at zero). |
| `require-revert-in-loop` | 7 | A revert inside a loop; batch operations revert as a whole. |
| `missing-zero-check` | 6 | An address parameter stored without a zero-address check. |
| `non-reentrant-not-first` | 4 | `nonReentrant` is not the first modifier. |
| `arbitrary-send-eth` | 4 | ETH sent to an address that is not `msg.sender`; recipients come from recorded accounting. |
| `missing-events-access-control` | 3 | An owner-only setter without an event. |
| `encode-packed-collision` | 1 | Standard CREATE2 init-code hash: creation code plus ABI-encoded constructor arguments. |
| `divide-before-multiply` | 1 | Staking reward rate; the division is exact because the amount must be divisible by the duration first. |
| `boolean-cst` | 1 | Early return of a constant in `BlindAuction._revealSingleBid`. |

Any new warning in one of these categories should be reviewed, not added to the exclusion list.

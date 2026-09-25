# Linting

`forge lint` runs as part of the quality gates. Its scope and exclusions are configured in `foundry.toml`,
so the rules are visible in the repository rather than hidden in a CI file.

```bash
forge lint
```

```toml
[lint]
lint_on_build = false
ignore        = ["test/**", "script/**", "src/automation/chainlink/**"]
exclude_lints = ["block-timestamp"]
```

---

## 1. Scope

| Path | Linted | Why |
| --- | --- | --- |
| `src/core/**` | Yes | Protocol logic — the code whose behaviour has financial consequences |
| `src/factory/**`, `src/registries/**`, `src/governance/**`, `src/libraries/**`, `src/interfaces/**` | Yes | Protocol logic |
| `src/automation/*.sol` | Yes | The receiver is protocol logic |
| `src/automation/chainlink/**` | No | Chainlink's official template, vendored verbatim. Editing it would make the vendored copy diverge from upstream |
| `test/**` | No | Test code is checked by the test suite and by review, not by static analysis heuristics |
| `script/**` | No | Deployment scripts are operator tooling; their correctness is verified by tests, preflight, and post-deployment verification |

`lint_on_build = false` keeps `forge build --sizes` fast and keeps lint output out of the build log, so a lint
regression is noticed as a lint regression rather than as build noise.

## 2. The `block-timestamp` exclusion

`block-timestamp` is excluded globally, and the justification is structural rather than stylistic:
**time is a first-class domain concept in this protocol.** Auctions end, offers expire, raffles run on a
clock, mint windows open and close, staking programs are scheduled, and the Treasury's daily spend window
rolls over. Removing timestamps would remove the protocol's behaviour.

This exclusion is defensible precisely because the timestamp dependence is bounded and visible:

| Usage | Window width |
| --- | --- |
| Auction end / expiry | minutes to days |
| Offer expiry | caller-chosen |
| Reveal extension | 5 minutes |
| Anti-sniping extension | 5 minutes |
| Raffle end | caller-chosen |
| Mint window | caller-chosen |
| Reward program | caller-chosen |
| Treasury daily window | 24 hours |

The narrowest windows are the two 5-minute auction extensions and the 10-minute automation schedule-skew
bound. Those are the ones to think about when reasoning about validator timestamp manipulation; see
[security.md](security.md#6-economic-assumptions).

## 3. Remaining findings in `src/`

These are heuristic static-analysis outputs. They are kept **visible on purpose** and are not treated as a
security assessment; each one belongs on the checklist of the independent security review.

| Rule | Count | Meaning | Adjudication status |
| --- | --- | --- | --- |
| `reentrancy-events` | 76 | An event is emitted after an external call | Reviewed — events after external calls are emitted in the same function that already carries `nonReentrant`; ordering has no security consequence |
| `reentrancy-no-eth` | 33 | State is written after an external call | Reviewed — every flagged function carries `nonReentrant` |
| `reentrancy-eth` | 13 | State written after an external call that can transfer ETH | **Reviewed** — every flagged function carries `nonReentrant`; the correspondence is enumerated in [security.md](security.md#5-reentrancy-posture) |
| `unsafe-typecast` | 21 | A down-cast not guarded by `SafeCast` | Reviewed — the casts are on values whose bounds are enforced earlier in the same function |
| `uninitialized-local` | 11 | A local declared without an initial value | Reviewed — counters that start at zero by design |
| `require-revert-in-loop` | 7 | A revert inside a loop | Intentional — batch operations are all-or-nothing by design |
| `missing-zero-check` | 6 | An address parameter stored without a zero check | Under review — see §4 |
| `non-reentrant-not-first` | 4 | `nonReentrant` is not the first modifier | Reviewed — modifier order is deliberate where it appears |
| `arbitrary-send-eth` | 4 | ETH sent to an address that is not `msg.sender` | Reviewed — recipients come from recorded accounting, never from user input |
| `missing-events-access-control` | 3 | An owner-only setter without an event | Under review — see §4 |
| `encode-packed-collision` | 1 | `abi.encodePacked` with multiple dynamic arguments | Accepted — standard CREATE2 init-code hash (creation code + ABI-encoded constructor args) |
| `divide-before-multiply` | 1 | Division before multiplication in `Staking.scheduleRewardProgram` | **Documented false positive** — `rewardAmount` is required to be exactly divisible by the program duration, so the division is exact |
| `boolean-cst` | 1 | Early return of a constant | Reviewed — `BlindAuction._revealSingleBid` returns early for a fake bid |

Only the three items marked *Under review* are genuinely open. Everything else has been examined and
classified; none of them is a silent acceptance of a known bug.

## 4. Open items

### 4.1 `missing-zero-check` (6)

The six occurrences correspond to address parameters that are stored or used without an explicit
`address(0)` check. Two are safe by construction because a later call would revert on a zero address;
four are omissions. **Action:** add explicit zero-address checks with the contract's existing error type,
then remove this rule from the "under review" list.

### 4.2 `missing-events-access-control` (3)

Three owner-only setters do not emit an event. Every other privileged setter in the protocol does, so this
is an inconsistency rather than a policy. **Action:** add events to the three setters. Retrofitting events
matters specifically for the reconciliation work in [mainnet.md](mainnet.md) §12, where monitoring depends
on being able to see privileged changes.

## 5. Policy for new warnings

Any new warning in one of the categories above should be **reviewed, not added to the exclusion list.**

The workflow:

1. Decide whether the finding is a real defect, a documented false positive, or an accepted trade-off.
2. If it is a real defect — fix the code.
3. If it is a documented false positive — add a row to the table in §3 with the reason, so the next reader
   does not re-investigate it.
4. If it is an accepted trade-off — record it in [security.md](security.md#known-design-limitations) so it
   is visible to reviewers rather than buried in a lint baseline.
5. Never silence a category wholesale to make the linter quiet.

The exclusion list is deliberately short — one rule (`block-timestamp`) and three path scopes — and it
should stay that way. A long exclusion list turns a quality gate into a formality.

## 6. Relationship to formatting

`forge fmt` and `forge lint` are separate gates:

| Gate | Command | Current state |
| --- | --- | --- |
| Formatting | `forge fmt --check` | Enforced in CI |
| Static analysis | `forge lint` | Enforced in CI; reviewed warnings remain visible |

Formatting and linting run as separate CI steps so failures are attributable to the correct quality gate.

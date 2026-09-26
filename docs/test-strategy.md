# Test Strategy

Verification in this repository is layered by **behaviour** and **execution model**. The organising
principle is simple: a test exists because it specifies a behaviour or a property that would otherwise be
unstated. Coverage is a diagnostic signal that helps find gaps; it is never the specification.

---

## 1. Why layered

A single test type cannot answer every question that matters. The layers exist because each one is capable
of proving a different kind of claim.

| Layer | Answers | Cannot answer |
| --- | --- | --- |
| Unit | "Does this function do exactly this, including at the boundaries?" | "Does the system stay correct across a sequence of calls?" |
| Integration | "Do these contracts compose correctly?" | "Does it hold for arbitrary inputs?" |
| Fuzz | "Does the property hold for a wide input space?" | "Does it hold after an adversarial sequence of state changes?" |
| Invariant | "Do the accounting relationships survive arbitrary action sequences?" | "Is the specified behaviour the *right* behaviour?" |
| Security | "Can an attacker do the thing they want to do?" | "Is there an attack nobody thought of?" |
| Fork | "Does this work against real deployed state and real external contracts?" | "Does it work on every target chain by default?" |
| Regression | "Is this specific past bug still fixed?" | Anything general |
| Upgrade | "Does an implementation change preserve storage and authority?" | Behaviour of new logic (that is Unit's job) |
| Conformance | "Does this comply with an external standard?" | Protocol-specific semantics |
| Deployment | "Is the deployed system wired the way the runbook claims?" | Behaviour of individual functions |

The layering is not a hierarchy of importance. A missing `Fuzz` suite for a contract whose arithmetic is
trivial is intentional, not an oversight — see §6.

---

## 2. Domain-first organisation

Tests are organised around the system boundary under verification, and the methodology appears as a
**filename suffix**:

```text
test/
├── auctions/{blind,dutch,open}/    BlindAuction.Fuzz.t.sol, DutchAuction.Invariant.t.sol, …
├── automation/
├── factory/
├── governance/
├── libraries/
├── marketplace/
├── nft/
├── payment/
├── protocol/
├── raffle/
├── registry/
├── staking/
├── support/
└── treasury/
```

The alternative — global `unit/`, `fuzz/`, `invariant/` trees — was rejected because it forces a reader to
jump between directories to understand one contract. With domain-first organisation, everything about
`Marketplace` is in `test/marketplace/`, and the suffix tells you how it is being verified.

Methodology suffixes in use:

| Suffix | Meaning |
| --- | --- |
| `.Unit.t.sol` | Deterministic local behaviour, boundaries, reverts, events, focused accounting |
| `.Integration.t.sol` | Multi-contract flows and protocol boundaries |
| `.Fuzz.t.sol` | Variable inputs with explicit arithmetic/accounting/state properties |
| `.Invariant.t.sol` | Stateful properties across action sequences with handlers or actors |
| `.Security.t.sol` | Adversarial authorisation, callbacks, reentrancy, griefing, failure behaviour |
| `.Fork.t.sol` | Behaviour that materially depends on real chain state or external deployment semantics |
| `.Regression.t.sol` | A permanent reproduction of a previously discovered bug |
| `.Upgrade.t.sol` | UUPS initialisation, authorisation, storage preservation, proxy behaviour |
| `.Conformance.t.sol` | Compatibility with an external standard or interface |
| `.Deployment.t.sol` | Wiring and deployed-system assumptions |
| No suffix | Domain-specific verification that does not fit one of the above (libraries, signed orders, automation) |

---

## 3. What each layer is asked to prove

### 3.1 Unit

Boundaries are the point, not the happy path. A unit suite is expected to cover:

- zero and maximum values for every numeric parameter,
- every revert condition with the **specific** error,
- every state transition, including illegal ones,
- event emission with exact arguments,
- authorisation for every gated function, including the negative case.

### 3.2 Fuzz

Fuzz targets are chosen where the input space is genuinely dangerous: fee arithmetic, price interpolation,
ticket-index selection, time bounds, and signature parameters. A fuzz test in this repository asserts a
*property* (monotonicity, conservation, bounds) rather than re-implementing the function.

### 3.3 Invariant

Invariant suites use handlers and modelled actors to drive state through realistic sequences. The
properties asserted are the same accounting relations the contracts assert at runtime, extended to
arbitrary interleavings:

- escrow solvency per domain,
- liability conservation in the ledgers,
- registry record consistency,
- creator index consistency in the Factory,
- state-machine reachability (no path leaves an auction permanently unfinalisable).

`fail_on_revert = false` in the default and `ci` profiles is a deliberate setting: a revert inside a
handler is a legitimate outcome that the invariant must tolerate, not an error.

### 3.4 Security

Security suites encode attacker capabilities rather than happy paths: unauthorised callers, replay,
callback spoofing, reentrancy, griefing, and partial-failure behaviour. If a security test passes for the
wrong reason — for example because a modifier happens to be first in the list — the test is wrong and
should be rewritten against the actual gate.

### 3.5 Fork

Fork testing is expensive and brittle, so it is reserved for cases where it is the *only* honest way to
verify a claim. There is exactly one fork suite today:
`test/raffle/Raffle.Fork.t.sol`, the release gate for the Chainlink VRF integration. It is designed to
**avoid mutating live subscription state**.

### 3.6 Meta-verification

```text
verification/
├── mutation/
│   ├── gambit.json     controlled source mutations
│   └── run.sh
└── symbolic/
    ├── AuctionMathHarness.sol
    ├── FeeMathHarness.sol
    ├── RewardMathHarness.sol
    └── run.sh
```

- **Mutation testing** asks whether the suite would *notice* a small, deliberate change to the source. A
  surviving mutant is a test-strength finding, not a false positive.
- **Symbolic verification** asks whether arithmetic properties hold for all inputs, not just sampled ones.

Neither layer is a substitute for behavioural testing, and neither is used to justify removing a
behavioural test.

---

## 4. Current scale

Measured on the working tree at the time of the last documentation sync:

```bash
find test -name '*.t.sol' | wc -l                                    # 84
grep -rhcE '^\s*function test' test --include='*.t.sol' | ...        # 638
grep -rhcE '^\s*function invariant' test --include='*.t.sol' | ...   # 14
```

| Metric | Value |
| --- | --- |
| `.t.sol` files | 84 |
| Test contracts | 110 |
| Test functions | 638 |
| Invariant functions | 14 |
| Combined verification entry points | 652 |
| Domain directories | 13, plus the shared `test/support/` tree and its three auction subdomains |

These are **static counts from the source tree**, not a `forge test` summary. The pass/fail summary from a
run is recorded separately in [coverage-baseline.md](coverage-baseline.md#history).

---

## 5. Execution profiles

| Profile | Fuzz runs | Invariant runs × depth | Where |
| --- | --- | --- | --- |
| `default` | 512 | 128 × 128 | Local iteration, `forge test` |
| `ci` | 4096 | 512 × 256 | `FOUNDRY_PROFILE=ci forge test --match-test 'testFuzz_'`, `FOUNDRY_PROFILE=ci forge test --match-test 'invariant_'`, CI |
| `ci-fast` | 256 | 64 × 64 | Pre-flight sanity before spending CI minutes |

`FOUNDRY_PROFILE=ci forge test --match-test 'testFuzz_'` and `FOUNDRY_PROFILE=ci forge test --match-test 'invariant_'` always run under `FOUNDRY_PROFILE=ci`. Running the heavier profile is the
default for those two targets on purpose: a fuzz suite that has not been run at 4096 runs has not really
been run.

---

## 6. When a suffix is intentionally absent

Not every domain receives every suffix. Missing suffixes are a statement about risk, not about effort:

The complete methodology distribution, counted from the tree:

| Suffix | Suites | Present in | Absent from |
| --- | --- | --- | --- |
| `Unit` | 12 | `auctions/{blind,dutch,open}`, `factory`, `governance`, `marketplace`, `nft`, `payment`, `raffle`, `registry`, `staking`, `treasury` | `automation`, `protocol`, `libraries` |
| `Security` | 12 | the same twelve domains as `Unit` | `automation`, `protocol`, `libraries` |
| `Fuzz` | 11 | the twelve `Security` domains except `governance` | `governance`, `automation`, `protocol`, `libraries` |
| `Invariant` | 11 | the same eleven domains as `Fuzz` | `governance`, `automation`, `protocol`, `libraries` |
| `Integration` | 10 | the eleven `Fuzz` domains except `nft` and `registry`, plus `protocol` | `nft`, `registry`, `automation`, `libraries` |
| `Regression` | 7 | `marketplace`, `raffle`, `staking`, `auctions/blind`, `auctions/open`, `factory`, `payment` | `auctions/dutch`, `treasury`, `registry`, `governance`, `nft`, `protocol`, `automation`, `libraries` |
| `Conformance` | 2 | `nft`, `registry` | everything else |
| `Fork` | 1 | `raffle` | everything else |
| `Upgrade` | 1 | `marketplace` | everything else |
| `Deployment` | 1 | `protocol` | everything else |

Beyond the ten methodology suffixes, exactly one suite carries a domain-specific suffix:
`marketplace/Marketplace.SignedOrders.t.sol`. The remaining 15 suites are unsuffixed: the nine library
suites and the six automation suites.

The reasons behind the absences:

| Absent | Why |
| --- | --- |
| `Fuzz` in `governance` | `ProtocolTimelock` is a ten-line subclass of OpenZeppelin's audited controller; all behaviour is inherited |
| `Fuzz` in `automation` | Receiver behaviour is combinatorial over discrete branches; per-branch validation tests plus measured gas cover the risk better than random inputs |
| `Fuzz` in `libraries` | The library suites are explicitly enumerated edge-case tests; the arithmetic that benefits from random sampling is covered by the domain fuzz suites and by `verification/symbolic/` |
| `Fuzz` in `protocol` | System-level suites are about wiring, not input spaces |
| `Invariant` in `governance` | No mutable protocol state exists in the contract |
| `Invariant` in `libraries` | Pure functions have no state to hold an invariant |
| `Invariant` in `automation` | The receiver's only persistent state is the replay map, and replay rejection is asserted directly in the validation suite |
| `Invariant` in `protocol` | Domain invariants are asserted where the state lives; a system-level invariant suite would duplicate them |
| `Upgrade` everywhere except `Marketplace` | No other contract is upgradeable (design rule 4 in [architecture.md](architecture.md)) |
| `Fork` everywhere except `raffle` | Only VRF semantics depend materially on live external state |
| `Conformance` everywhere except `nft` and `registry` | Only those two implement an external standard or interface contract |
| `Regression` in the eight listed domains | No bug has been discovered there yet. **This is a policy, not an accident:** the suite is created the moment a bug is found and is never deleted — which is why the seven domains above already have one |

The last row is a policy, not an accident: a regression suite is created the moment a bug is found, and it
is never deleted. That is why `marketplace`, `raffle`, `staking`, `blind`, `open`, `factory`, and `payment`
already have one.

---

## 7. Quality rules

These are enforced by review, not by tooling:

1. **No coverage-padding tests.** A test that exists only to execute a line is a liability: it costs CI
   time and creates false confidence.
2. **No test asserts an implementation detail.** Tests assert behaviour or properties. If refactoring a
   private function breaks a test, the test was testing the wrong thing.
3. **Reverts are asserted with the specific error**, not with `vm.expectRevert()` and no argument.
4. **A regression test carries a comment explaining the original bug**, so a future maintainer does not
   "fix" the test.
5. **Duplicated suites are merged or deleted.** Two suites asserting the same property is a maintenance
   cost with no verification benefit.
6. **Every invariant maps to a runtime assertion or a stated design property.** An invariant nobody would
   ever enforce in production is a property of the test, not of the protocol.

---

## 8. What this strategy does not claim

- A passing suite does not imply the absence of bugs, and it does not imply an audit.
- Coverage percentages are diagnostics; the interpretation rules are in
  [coverage-baseline.md](coverage-baseline.md#interpretation).
- Fork coverage exists for one integration. Target-chain behaviour for chains other than the one the fork
  suite targets is assumed, not verified.
- Deployment scripts are verified by tests, but a script that works in a test can still be misconfigured
  in production. `forge script script/Preflight.s.sol --rpc-url "$RPC_URL"` exists for exactly that gap.

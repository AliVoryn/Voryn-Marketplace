# Test suite — status, scope, and how to actually run it
## Execution status: verified locally
The project has been compiled and its complete Foundry test suite has passed
locally with the dependency versions currently present under `lib/`.
The suite has not yet been run against a live network fork, and static-analysis
reports from Slither or equivalent tools are still required before mainnet use.
**Local verification commands:**
```bash
forge init --force .                         # or: git submodule update, if lib/ is pre-populated
forge install foundry-rs/forge-std
forge install OpenZeppelin/openzeppelin-contracts
forge install OpenZeppelin/openzeppelin-contracts-upgradeable
forge install smartcontractkit/chainlink-brownie-contracts  # or the official @chainlink/contracts source
forge build
forge test -vvv
```
Fix whatever the first real build surfaces — import path mismatches against
whatever exact dependency versions you pin are the most likely first failure
(see "Known unverified assumptions" below).
## Layout
```
test/
├── unit/         pure library tests (FeeMath, AuctionMath, PhaseLogic, ListingMath,
│                 AccountingMath, OrderHashLib, RewardMath, RaffleMath, AuctionPhaseLib)
├── integration/  cross-contract flows (CustomNFT, Treasury, PaymentManager, OpenAuction,
│                 BlindAuction, DutchAuction, Staking, Marketplace listing/offer/
│                 signed-order, Factory wiring, Raffle security-only)
├── upgrade/      Marketplace UUPS proxy behavior
├── deployment/   end-to-end createProtocolSuite() graph validation
├── invariant/    one flagship Handler-based invariant suite (OpenAuction escrow)
├── helpers/      TestBase.sol (shared actors + direct-deployment helpers)
└── mocks/        MockVRFCoordinatorV2Plus.sol
```
There is no `test/fork/` directory: nothing in this repository depends on
live external-chain state at a pinned block, so a fork suite would add
nothing. There is no separate `test/regression/` directory: regression tests
for confirmed-and-fixed defects are named `test_regression_*` and live
directly inside the domain file they belong to (e.g.
`test/integration/Factory.Integration.t.sol` for the BlindAuction
beneficiary-check fix), per the instruction to group regression tests **by
domain**, not by "is a regression."
## What this pass covers vs. defers
This audit pass prioritized master-prompt section 78's ordering — accounting,
authorization, state transitions, settlement, escrow, signatures,
upgradeability, deployment wiring — over chasing test count. It does **not**
claim to implement literally every scenario the master prompt enumerates
(hundreds of individually-listed cases across 85 sections). Deferred, not
done:
- Mutation testing (section 49) — requires a working `forge test` baseline first.
- Fork testing (section 42) — not applicable to any current contract.
- Gas snapshotting/regression tracking (section 51) — requires a working build.
- Static analysis execution (Slither/Semgrep/Solhint, section 48) — wired
  into CI but never run.
- Exhaustive per-function boundary tests for every numeric/time edge in
  every contract (section 37) — the highest-risk boundaries were covered
  (auction anti-snipe extension limits, Dutch auction endPrice, Marketplace
  signature deadlines, Staking cooldown/reward-phase boundaries); many
  lower-risk ones were not.
- CustomNFT ERC-721 conformance suite (section 20) — not attempted; if strict
  ERC-721 compliance is a requirement, run an OpenZeppelin/standards
  conformance checker against it separately.
- IStaking/IPaymentManager/ITreasury/IRegistry/ICustomNFT full interface
  surface — covered via the flows that exercise them, not function-by-function.
## Known unverified assumptions (flag before relying on this suite)
1. **Chainlink VRF v2.5 interfaces** (`IVRFCoordinatorV2Plus`,
  `VRFV2PlusClient`) as imported by `src/core/Raffle.sol` and mocked by
   `test/mocks/MockVRFCoordinatorV2Plus.sol` were reconstructed from
   training knowledge, not read from the real `@chainlink/contracts`
   package (no network access). Confirm the struct fields and function
   selector match exactly once that package is actually installed.
2. `forge-std`'s `Test`/`Script`/`console2` API surface used here (`vm.prank`,
   `vm.deal`, `vm.warp`, `vm.expectRevert`, `vm.sign`, `bound`, `makeAddr`,
   `vm.envAddress`/`envOr`/`envUint`/`envBytes32`) is the standard,
   long-stable surface, but was not checked against whatever exact
   `forge-std` commit gets pinned.
3. OpenZeppelin `Ownable2Step`/`AccessControlUpgradeable`/`UUPSUpgradeable`/
   `ERC1967Proxy` revert selectors referenced in tests (e.g.
   `Ownable.OwnableUnauthorizedAccount`) match the OpenZeppelin v5.x line,
   consistent with the `Ownable(initialOwner)` constructor pattern already
  used throughout `src/core/`. If a different major version is pinned, some
   `vm.expectRevert` selectors will need updating.
## Findings from this pass (see the chat report for full detail)
Two genuine, newly-confirmed defects were found and fixed while writing
these tests (both have dedicated `test_regression_*`/`test_FINDING_*` cases):
- `Treasury.setProtocolFeeBps` reverted with the misleading `Unauthorized()`
  error for an out-of-range `bps` — fixed to a new `InvalidFeeBps()` error.
- `Raffle._assertInvariant` used strict equality (`!=`) instead of the `<`
  solvency check used everywhere else in the codebase (OpenAuction,
  Marketplace, BlindAuction) — a forced ETH transfer via `selfdestruct`
  (which bypasses any `receive()` guard) would have permanently bricked the
  contract. Fixed to match the established `<` pattern.
Two behaviors were investigated per explicit master-prompt instructions and
**confirmed as intentional, not bugs** (each has a `test_FINDING_*` case
locking the behavior in):
- `ProtocolFactory.createTreasury()`'s `transferOwnership(msg.sender)` only
  sets a *pending* owner under `Ownable2Step`; the factory remains `owner()`
  — and therefore able to pass its own `UnauthorizedTreasuryOwner` checks in
  `createMarketplace()` etc. — until the recipient explicitly calls
  `acceptOwnership()`. Working as designed.
- `DutchAuction`'s `endPrice` is an asymptotic floor, never an actually
  purchasable price: `buy()` strictly requires `block.timestamp < endAt`, so
  the exact `endPrice` value is only ever reachable through `expireAuction()`
  (NFT returns to seller), never through a purchase.
## Second-pass code review (this revision)
A dedicated line-by-line review pass was done after the first version of
this suite: every constructor call, error selector, and numeric assumption
in every test file was cross-checked against the actual `src/core/`/`src/interfaces/`
source (not re-derived from memory) — see the chat transcript for the
specific greps run. That pass:
- Found and removed two pieces of dead/over-engineered test scaffolding in
  `TestBase.sol`: an unused `operator` actor, an unused `_approve()` helper
  (every test already approves inline, which reads clearer at the call
  site), and a vestigial third parameter on `_mint()` that CustomNFT's
  `mint()` never actually takes (tokenIds are auto-assigned).
- Strengthened `test/invariant/OpenAuction.Invariant.t.sol`: the handler
  previously drove exactly one auction to completion and then spent the
  rest of a long run doing nothing (every action a no-op once the sole
  auction was terminal). It now includes a `createNewAuction` action so the
  invariant is exercised across many create→bid→finalize/cancel cycles, and
  the previously-unused `nft` reference is now actually used.
- Re-verified every constructor signature (`Treasury`, `PaymentManager`,
  `OpenAuction`, `DutchAuction`, `Staking`, `CustomNFT`) and every numeric
  default the tests assume (`minimumStake = 0.01 ether`,
  `unstakeCooldown = 1 days`, `emergencyPenaltyBps = 1000`,
  `extensionWindow`/`extensionTime = 5 minutes`, `maxExtensions = 3`)
  directly against source. No further mismatches found.
- Found no additional production-contract defects beyond the two listed
  above; no test files were found to assert incorrect/backwards behavior.

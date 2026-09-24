# Test Matrix

Every suite in `test/`, what it covers, and how to run it in isolation. Counts are static counts of
`function test*` and `function invariant*` declarations in the source tree.

**Totals:** 84 `.t.sol` files · 110 test contracts · 638 test functions · 14 invariant functions ·
**652 combined verification entry points**.

---

## 1. Suite inventory

### 1.1 Auctions — blind

`test/auctions/blind/`

| Suite | Tests | Covers |
| --- | --- | --- |
| `BlindAuction.Unit.t.sol` | 36 | Commitment hashing, phase transitions, deposit accounting, reveal validation, withdrawal paths, events, revert conditions |
| `BlindAuction.Security.t.sol` | 8 | Commitment replay, spoofed reveals, unauthorised finalisation, seller bidding, direct-payment rejection |
| `BlindAuction.Regression.t.sol` | 5 | Permanent reproductions of previously fixed blind-auction defects |
| `BlindAuction.Fuzz.t.sol` | 2 | Deposit and refund arithmetic over variable bid sequences |
| `BlindAuction.Integration.t.sol` | 1 | Factory-created blind auction end to end against a real `Treasury` |
| `BlindAuction.Invariant.t.sol` | 1 invariant | Escrow solvency across arbitrary interleavings of bid, reveal, finalise, withdraw, cancel |

### 1.2 Auctions — Dutch

`test/auctions/dutch/`

| Suite | Tests | Covers |
| --- | --- | --- |
| `DutchAuction.Unit.t.sol` | 28 | Price interpolation, clamping at the boundaries, purchase flow, excess refund, cancel and expire gates |
| `DutchAuction.Security.t.sol` | 3 | Underpayment, seller self-purchase, unauthorised cancellation |
| `DutchAuction.Fuzz.t.sol` | 2 | Monotonic price decay and `msg.value >= currentPrice` boundary behaviour |
| `DutchAuction.Integration.t.sol` | 2 | Fee routing into the Treasury and NFT escrow release |
| `DutchAuction.Invariant.t.sol` | 2 invariants | Price monotonicity and terminal-state consistency |

### 1.3 Auctions — open

`test/auctions/open/`

| Suite | Tests | Covers |
| --- | --- | --- |
| `OpenAuction.Unit.t.sol` | 37 | Bid floor, increment enforcement, anti-sniping extension, buyout, phase machine, refund withdrawal |
| `OpenAuction.Security.t.sol` | 7 | Seller bidding, refund theft, unauthorised cancel, reentrancy on refund withdrawal, direct payments |
| `OpenAuction.Regression.t.sol` | 5 | Permanent reproductions of previously fixed open-auction defects |
| `OpenAuction.Fuzz.t.sol` | 2 | Bid amounts and extension counters across variable sequences |
| `OpenAuction.Integration.t.sol` | 2 | Settlement through the Treasury with fee split verification |
| `OpenAuction.Invariant.t.sol` | 1 invariant | `balance >= totalActiveBidLiability + totalRefundLiability` |

### 1.4 Automation

`test/automation/` — shared wiring lives in `test/support/AutomationIntegrationBase.sol`.

| Suite | Tests | Covers |
| --- | --- | --- |
| `ProtocolAutomationReceiver.t.sol` | 12 | Forwarder gate, workflow identity requirement, payload shape, pause semantics, ownership, simulation-receiver detection |
| `ProtocolAutomationValidation.t.sol` | 15 | Every `_validate` branch: registry record, kind mismatch, chain selector, schedule skew, refund batch bounds, refund cursor staleness, replay |
| `AutomationDiscovery.t.sol` | 11 | `AutomationScanLib.window`/`capacity` and the bounded, rotating discovery views including the 500-id and 100-item hard caps |
| `ProtocolAutomationIntegration.t.sol` | 8 | Per-action dispatch through the receiver into the real domain contracts |
| `ProtocolAutomationGas.t.sol` | 8 | Measured gas for each action against the configured `gasLimit` and `refundBatchSize` |
| `AutomationScripts.t.sol` | 3 | The deployment and configuration scripts for the receiver |

The TypeScript workflow tests are separate: see
[`cre/protocol-automation/README.md`](../cre/protocol-automation/README.md).

### 1.5 Factory

`test/factory/`

| Suite | Tests | Covers |
| --- | --- | --- |
| `ProtocolFactory.Integration.t.sol` | 22 | Every creation path, full-suite wiring, controller finalisation, registry registration, ownership handoff |
| `ProtocolFactory.Security.t.sol` | 17 | Treasury-authority enforcement, salt reuse, unauthorised payer granting, NFT ownership checks, zero-address rejection |
| `ProtocolFactory.Unit.t.sol` | 16 | Constants, kinds, per-creator indexing, address prediction |
| `ProtocolFactory.Regression.t.sol` | 4 | Permanent reproductions of previously fixed factory defects |
| `ProtocolFactory.Fuzz.t.sol` | 2 | Deterministic address prediction across variable salts and creators |
| `ProtocolFactory.Invariant.t.sol` | 1 invariant | Creator-index consistency: every registered instance appears exactly once in its creator's list |

### 1.6 Governance

`test/governance/`

| Suite | Tests | Covers |
| --- | --- | --- |
| `ProtocolGovernance.Integration.t.sol` | 6 | Scheduling and executing ownership acceptance through a live `ProtocolTimelock` |
| `ProtocolGovernance.Security.t.sol` | 2 | The delay cannot be bypassed; unauthorised callers cannot schedule |
| `ProtocolGovernance.Unit.t.sol` | 1 | Constructor arguments land in the inherited controller |

### 1.7 Libraries

`test/libraries/` — no methodology suffix; a library's contract is its function signature.

| Suite | Tests | Covers |
| --- | --- | --- |
| `AuctionPhaseLib.t.sol` | 15 | Phase derivation from the clock, `requirePhase`, time remaining, extension rules |
| `AuctionMath.t.sol` | 10 | Minimum bid computation, extension predicate |
| `RaffleMath.t.sol` | 10 | Uniform ticket pick, entrant binary search across spans |
| `RewardMath.t.sol` | 9 | Accumulator arithmetic and precision bounds |
| `AccountingMath.t.sol` | 7 | Solvency arithmetic flooring at zero |
| `FeeMath.t.sol` | 6 | Fee split conservation, `bps` boundary handling |
| `ListingMath.t.sol` | 5 | Active/stale predicates |
| `OrderHashLib.t.sol` | 2 | EIP-712 struct hash stability |
| `PhaseLogic.t.sol` | 2 | Deadline predicate |

### 1.8 Marketplace

`test/marketplace/`

| Suite | Tests | Covers |
| --- | --- | --- |
| `Marketplace.Unit.t.sol` | 47 | Listing lifecycle, offer lifecycle, expiry, batch cancel, fee configuration, admin setters, role gates |
| `Marketplace.SignedOrders.t.sol` | 16 | EIP-712 order hashing, nonce consumption, relayer submission, malformed signatures, nonce invalidation |
| `Marketplace.Upgrade.t.sol` | 5 | UUPS authorisation, storage preservation, re-initialisation rejection |
| `Marketplace.Security.t.sol` | 4 | Cross-account refunds, unauthorised upgrades, dependency swapping without authorisation, escrow invariant |
| `Marketplace.Fuzz.t.sol` | 3 | Fee split conservation and escrow conservation over variable prices |
| `Marketplace.Integration.t.sol` | 3 | Treasury and PaymentManager integration on the sale and refund paths |
| `Marketplace.Regression.t.sol` | 1 | Permanent reproduction of a previously fixed defect |
| `Marketplace.Invariant.t.sol` | 1 invariant | Offer escrow solvency across arbitrary action sequences |

### 1.9 NFT

`test/nft/`

| Suite | Tests | Covers |
| --- | --- | --- |
| `CustomNFT.Unit.t.sol` | 30 | Mint, batch mint, burn, approvals, metadata, enumeration, mint-window phases, wallet limits, supply cap |
| `CustomNFT.Security.t.sol` | 5 | Unauthorised minting and metadata writes, receiver-hook rejection, pause semantics |
| `CustomNFT.Conformance.t.sol` | 2 | ERC-165 / ERC-721 / ERC-721 Metadata interface compliance told against an independent standard checklist |
| `CustomNFT.Fuzz.t.sol` | 1 | Batch sizes and wallet limits over variable inputs |
| `CustomNFT.Invariant.t.sol` | 3 invariants | Supply conservation, ownership/balance consistency, enumeration consistency |

### 1.10 Payment

`test/payment/`

| Suite | Tests | Covers |
| --- | --- | --- |
| `PaymentManager.Unit.t.sol` | 14 | Credit attribution, withdrawal, creditor authorisation, controller lifecycle |
| `PaymentManager.Security.t.sol` | 4 | Unauthorised credits, double withdrawal, direct payments, reentrancy |
| `PaymentManager.Fuzz.t.sol` | 2 | `totalClaimable` conservation |
| `PaymentManager.Regression.t.sol` | 1 | Permanent reproduction of a previously fixed defect |
| `PaymentManager.Invariant.t.sol` | 1 invariant | `totalClaimable <= balance` |

### 1.11 Protocol (system level)

`test/protocol/`

| Suite | Tests | Covers |
| --- | --- | --- |
| `Protocol.Integration.t.sol` | 4 | Cross-domain flows over a deployed suite |
| `Protocol.Deployment.t.sol` | 2 | Dependency wiring and post-deployment behaviour of a full deployment |

### 1.12 Raffle

`test/raffle/`

| Suite | Tests | Covers |
| --- | --- | --- |
| `Raffle.Security.t.sol` | 39 | Callback spoofing, request-id mismatch, phase laundering, ticket-cap bypass, refund theft, refund batching, cursor manipulation, direct payments |
| `Raffle.Unit.t.sol` | 10 | Creation validation, ticket purchase accounting, VRF config validation, cancellation paths |
| `Raffle.Fuzz.t.sol` | 6 | Ticket arithmetic, winner selection distribution bounds, refund totals |
| `Raffle.Integration.t.sol` | 4 | Full cycle against `MockVRFCoordinatorV2Plus`, including a measured fulfillment gas log |
| `Raffle.Regression.t.sol` | 2 | Permanent reproductions of previously fixed raffle defects |
| `Raffle.Fork.t.sol` | 1 | **Release gate.** Real VRF coordinator semantics against forked state, without mutating live subscription state |
| `Raffle.Invariant.t.sol` | 1 invariant | `balance >= totalActiveRaffleFunds + totalRaffleRefundLiability` |

### 1.13 Registry

`test/registry/`

| Suite | Tests | Covers |
| --- | --- | --- |
| `ProtocolRegistry.Unit.t.sol` | 7 | Registration validation, activation toggling, indexed enumeration |
| `ProtocolRegistry.Conformance.t.sol` | 7 | `IRegistry` interface contract compliance |
| `ProtocolRegistry.Security.t.sol` | 4 | Unauthorised registrar, duplicate registration, instance replacement, inactive-instance discovery filtering |
| `ProtocolRegistry.Fuzz.t.sol` | 2 | Window and cycle derivation over variable offsets |
| `ProtocolRegistry.Invariant.t.sol` | 1 invariant | Every record's `instance` has code and appears in its kind index |

### 1.14 Staking

`test/staking/`

| Suite | Tests | Covers |
| --- | --- | --- |
| `Staking.Unit.t.sol` | 34 | Stake/unstake bounds, cooldown, program scheduling and divisibility, claim, compound, emergency penalty, bounds configuration |
| `Staking.Integration.t.sol` | 3 | Treasury-funded reward program end to end |
| `Staking.Security.t.sol` | 3 | Double claiming, unauthorised funding, cooldown bypass |
| `Staking.Fuzz.t.sol` | 3 | Reward accrual conservation over variable amounts and durations |
| `Staking.Regression.t.sol` | 1 | Permanent reproduction of a previously fixed defect |
| `Staking.Invariant.t.sol` | 1 invariant | `balance >= totalStaked + totalRewardLiability + rewardReserve` |

### 1.15 Treasury

`test/treasury/`

| Suite | Tests | Covers |
| --- | --- | --- |
| `Treasury.Unit.t.sol` | 24 | Credit, pay, claim, daily limits, fee recipient, controller lifecycle, rescue bounds |
| `Treasury.Security.t.sol` | 5 | Unauthorised payers, liability draining, rescue beyond available balance, reentrancy |
| `Treasury.Integration.t.sol` | 4 | Domain credits landing as claimable balances and being withdrawn |
| `Treasury.Fuzz.t.sol` | 2 | `availableBalance` and `totalLiabilities` consistency |
| `Treasury.Invariant.t.sol` | 1 invariant | Liabilities never exceed the balance; `availableBalance() >= 0` |

### 1.16 Support

`test/support/` — not a suite; shared infrastructure.

| File | Purpose |
| --- | --- |
| `TestBase.sol` | Common deployment and actor setup used by the domain suites |
| `AutomationIntegrationBase.sol` | Registry, receiver, and forwarder wiring for the automation suites |
| `mocks/MockVRFCoordinatorV2Plus.sol` | Deterministic VRF coordinator for raffle tests |
| `actors/`, `fixtures/`, `handlers/` | Reserved directories; suites keep their own handlers close to the suite |

---

## 2. Coverage by verification model

| Suffix | Suites | Notes |
| --- | --- | --- |
| `Unit` | 12 | Every domain with mutable state |
| `Security` | 12 | Every domain plus system-level |
| `Fuzz` | 11 | Absent for `governance` (inherited audited logic) and `automation` (discrete branches) |
| `Invariant` | 11 | 14 invariant functions total; `CustomNFT` has 3, `DutchAuction` has 2 |
| `Integration` | 10 | — |
| `Regression` | 7 | Grows monotonically; never shrinks |
| `Conformance` | 2 | `CustomNFT` (ERC-721), `ProtocolRegistry` (IRegistry) |
| `Fork` | 1 | `Raffle` — the only place live external semantics matter |
| `Upgrade` | 1 | `Marketplace` — the only upgradeable contract |
| `Deployment` | 1 | `Protocol.Deployment` |
| Unsuffixed | 16 | 9 library suites, 6 automation suites, 1 signed-orders suite |

Arithmetic: 68 suffix-carrying files + 16 unsuffixed files = 84 `.t.sol` files. `Protocol.Integration.t.sol`
carries the `Integration` suffix and is counted in that row, not here.

---

## 3. Running suites

```bash
# A single file
forge test --match-path 'test/raffle/Raffle.Security.t.sol'

# Every methodology for one contract
forge test --match-contract Marketplace

# One auction domain
forge test --match-path 'test/auctions/**'

# Only fuzz tests, at the CI profile
make fuzz

# Only invariants, at the CI profile
make invariant

# Only the fork gate
make fork                     # requires RPC_URL

# Fast sanity pass over everything
FOUNDRY_PROFILE=ci-fast forge test
```

---

## 4. Reading a failure

Because suites are domain-scoped and methodology-suffixed, the failure location usually identifies the
question that failed:

| Failing suffix | Usually means |
| --- | --- |
| `Unit` | Behaviour or a boundary changed — most likely a real regression |
| `Security` | An authorisation or accounting gate was weakened |
| `Fuzz` | An arithmetic property broke for some input — reproduce with the reported counterexample |
| `Invariant` | An accounting relation broke across sequences — check the handler that produced the sequence |
| `Fork` | Either the code changed or upstream state/behaviour changed; both require investigation |
| `Regression` | A previously fixed bug is back. Treat as the highest-priority failure in the tree |
| `Conformance` | The contract no longer satisfies an external standard — an integrator-visible break |
| `Upgrade` | A storage or authorisation change made an upgrade unsafe |
| `Deployment` | Wiring assumed by the runbook no longer holds |

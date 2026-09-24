# Feature Catalogue

Every user-facing and operator-facing capability in the protocol, grouped by domain, with the contract
that owns each behaviour and the test suites that pin it.

**How to read the tables.** "Guarantee" states what the implementation actually enforces, not what it
aspires to. Where a capability has a caveat, the caveat is stated in the same row rather than buried in a
footnote.

---

## 1. Marketplace

Contract: `src/core/Marketplace.sol` · Tests: `test/marketplace/`

### 1.1 Listings

| Capability | Guarantee |
| --- | --- |
| Create a listing | Only the current NFT owner can list; price must be non-zero; `expiresAt == 0` becomes `now + 7 days` |
| Fixed-price purchase | Exact payment required; seller cannot buy their own listing; NFT owner re-verified immediately before transfer |
| Update a listing | Seller only; re-verifies ownership; price and expiry validated |
| Cancel a listing | Seller only; reverts if the listing already expired, forcing `expireListing` instead |
| Batch cancel | 1–50 ids; all-or-nothing |
| Expire a listing | Permissionless once past `expiresAt` — anyone can clean up dead state |
| Signed listings | EIP-712 `ListingOrder` with a per-seller nonce; any relayer can submit; nonce increments atomically |
| Nonce invalidation | `invalidateNonce()` bumps the seller's nonce, invalidating every outstanding order at once |

### 1.2 Offers

| Capability | Guarantee |
| --- | --- |
| Make an offer | Escrows `msg.value`; `expiresAt` must be strictly in the future |
| Accept an offer | Only the current token owner; fee split applied to the offer amount; NFT transferred to the buyer |
| Reject an offer | Token owner only; buyer refunded through `PaymentManager` |
| Cancel an offer | Buyer only; refund through `PaymentManager` |
| Expire an offer | Permissionless after expiry; refund through `PaymentManager` |
| Escrow integrity | `address(this).balance >= totalOfferEscrow` asserted after every offer state change |

### 1.3 Fees

| Capability | Guarantee |
| --- | --- |
| Protocol fee | `protocolFeeBps`, ≤ 1000 (10%), initial value 250 (2.50%) |
| Minimum fee floor | `minimumFeeBps`, ≤ 1000, initial value 100 (1.00%); effective fee is `max(protocol, minimum)` |
| Per-account fee | `setCustomFee(account, bps, active)` overrides both, for either direction (lower or higher) |
| Fee destination | `Treasury.feeRecipientForProtocol()` |
| Proceeds destination | The seller's own Treasury claimable balance |

### 1.4 Operations

| Capability | Guarantee |
| --- | --- |
| Pause / unpause | `OPERATOR_ROLE` |
| Upgrade | UUPS, authorised by `DEFAULT_ADMIN_ROLE` only |
| Swap treasury | `ADMIN_ROLE`; the new treasury must already authorise this contract as a payer |
| Swap payment manager | `ADMIN_ROLE`; the new manager must already authorise this contract as a creditor |
| Automation | `automationDueOfferIds(cycle, maxScan, maxItems)` returns expired-but-open offers in a bounded window |

---

## 2. Open Auction

Contract: `src/core/OpenAuction.sol` · Tests: `test/auctions/open/`

| Capability | Guarantee |
| --- | --- |
| Create an auction | Reserve price and minimum increment both required; NFT escrowed; optional future `startAt` |
| Scheduled start | `Created`/`Scheduled` promotes to `Active` automatically on first interaction after `startAt` |
| Place a bid | ≥ reserve for the first bid, then ≥ `highestBid + minIncrement`; seller excluded |
| Anti-sniping | A bid inside the final 5 minutes extends the deadline by 5 minutes, up to 3 times |
| Buyout | Optional, configured by the seller or owner; must exceed the reserve; instantly finalises and refunds the standing highest bidder |
| End an auction | Permissionless after `endAt`; moves `Active → Ended` |
| Finalise | Successful → NFT to winner, proceeds split to fee recipient and seller. Unsuccessful → NFT to seller, highest bidder credited a pull-refund |
| Cancel | Seller or owner, before `endAt`; refunds the highest bidder and returns the NFT |
| Refunds | Pull-based via `withdrawRefund()`; `RefundWithdrawn` event on claim |
| Bid history | `bidHistoryLength` / `bidHistoryAt` return `(bidder, amount, timestamp)` snapshots |
| Escrow integrity | `balance >= totalActiveBidLiability + totalRefundLiability` asserted on every settlement path |
| Direct payments | Rejected — `receive()` reverts |

---

## 3. Blind Auction

Contract: `src/core/BlindAuction.sol` · Tests: `test/auctions/blind/`

| Capability | Guarantee |
| --- | --- |
| Commit a bid | `keccak256(abi.encodePacked(value, fake, secret))`; deposits escrowed; max 20 bids per address |
| Single-use commitments | A commitment hash can be used once — replay of another participant's commitment is impossible |
| Reveal | All three arrays must match the caller's bid count; refunds for losing/fake bids are credited automatically |
| Reveal extension | A valid reveal inside the last 5 minutes of the reveal window extends it by 5 minutes, up to 3 times |
| Finalise | Reserve met → NFT to winner, seller settled. Not met → NFT to the beneficiary, best bid credited to `pendingReturns` |
| Withdraw | Pull-based; available for pending returns |
| Withdraw unrevealed | Reclaims deposits for commitments never revealed; available from `AwaitingFinalization` onward |
| Cancel | Owner only, during bidding or reveal; NFT returns to the beneficiary |
| Cancel refund | `withdrawIfCancelled()` combines unrevealed deposits and pending returns |
| Escrow integrity | `balance >= totalPendingReturns + totalUnrevealedDeposits` asserted after each state change |
| NFT escrow check | Finalisation re-verifies the contract still owns the NFT before releasing it |
| Direct payments | Rejected — `receive()` reverts |

---

## 4. Dutch Auction

Contract: `src/core/DutchAuction.sol` · Tests: `test/auctions/dutch/`

| Capability | Guarantee |
| --- | --- |
| Create an auction | `startPrice > endPrice`; NFT escrowed; optional scheduled start |
| Declining price | Linear interpolation with `Math.mulDiv`, clamped to `startPrice`/`endPrice` at the boundaries |
| Buy | Requires `msg.value >= currentPrice`; excess refunded to the buyer inline; seller cannot buy |
| Cancel | Seller or owner, before `endAt`; NFT returned |
| Expire | Permissionless after `endAt`; NFT returned to seller |
| Fee | `FeeMath.split(currentPrice, protocolFeeBps)`; both parts credited to the Treasury (fee recipient and seller) |
| Automation | `automationDueIds` returns auctions past `endAt` still in `Created`/`Active` |
| Direct payments | Rejected — `receive()` reverts |

---

## 5. Raffle

Contract: `src/core/Raffle.sol` · Tests: `test/raffle/`

| Capability | Guarantee |
| --- | --- |
| Create a raffle | Creator must own the NFT; NFT escrowed; price, duration, and caps validated; `maxTickets` capped at `type(uint128).max` |
| Buy tickets | Per-wallet and per-raffle caps enforced; one `Entrant` span recorded per purchase for O(log n) winner lookup |
| Request randomness | Permissionless once sold out or past `endAt`; otherwise owner-driven retry after 1 hour |
| VRF callback | Coordinator identity and request binding verified before any state write; `randomWords.length == 1` |
| Winner selection | `randomWord % ticketsSold` mapped to an entrant by binary search over ticket spans |
| Finalisation inside callback | Fee split, proceeds credited to creator, NFT transferred — all inside `rawFulfillRandomWords` |
| Stuck raffle | After 24 hours in `AwaitingRandomness`, the creator can cancel; tickets become refundable |
| Refund processing | Cursor-based batching, 1–100 entrants per call, replay-safe through the on-chain cursor |
| Refund claim | Pull-based `claimRaffleRefund()` |
| Failed raffle | Zero tickets sold after `endAt` → `Failed`, NFT returned to creator |
| Cancel | Creator or owner, only with zero tickets sold |
| Escrow integrity | `balance >= totalActiveRaffleFunds + totalRaffleRefundLiability` asserted after every settlement |
| Direct payments | Rejected — `receive()` reverts |
| Automation | `automationCandidates` returns winner requests, failed raffles, and refund cursors in one bounded scan |

---

## 6. Staking

Contract: `src/core/Staking.sol` · Tests: `test/staking/`

| Capability | Guarantee |
| --- | --- |
| Fund rewards | Directly payable, or pulled from the Treasury by the owner with reason `STAKING_REWARD_FUNDING` |
| Schedule a program | `(startAt, endAt, rewardAmount)`; amount must be exactly divisible by duration; only one program at a time; validated against `rewardInventory()` |
| Stake | Enforces `minimumStake` (0.01 ETH default) and optional `maximumStake`; starts/refreshes a cooldown |
| Unstake | Requires the cooldown to have elapsed |
| Claim | Reverts if the payout is not covered by free inventory |
| Compound | Converts rewards into stake; re-checks the maximum |
| Emergency unstake | Immediate exit; forfeits accrued rewards; applies `emergencyPenaltyBps` (10% default); the penalty stays in the contract as available inventory |
| Cooldown | `unstakeCooldown`, default 1 day; refreshed on stake and compound |
| Bounds | `configureBounds(minimum, maximum)`; `maximum == 0` means unbounded |
| Invariant | `balance >= totalStaked + totalRewardLiability + rewardReserve` |
| Automation | None — staking is entirely user-driven by design |

---

## 7. Custom NFT

Contract: `src/core/CustomNFT.sol` · Tests: `test/nft/`

| Capability | Guarantee |
| --- | --- |
| Mint | `MINTER_ROLE`; gated by supply cap, wallet limit, and mint window |
| Batch mint | 1–100 tokens in one transaction; `MINTER_ROLE` |
| Mint window | `(startAt, endAt)`; unset bounds mean always active |
| Wallet limit | `walletMintLimit`; `0` means unlimited |
| Supply cap | Immutable `maxSupply`; `0` means unlimited |
| Burn | Owner or approved; removes it from the owner's enumeration |
| Metadata | Per-token `tokenURI` and collection-wide `baseURI`; `METADATA_ROLE` |
| Roles | `DEFAULT_ADMIN_ROLE`, `MINTER_ROLE`, `OPERATOR_ROLE`, `METADATA_ROLE` |
| Approval management | `approve`, `revokeApproval`, `setApprovalForAll` |
| Enumeration | `tokensOfOwner(owner)`, `walletMinted(owner)`, `totalSupply()`, `exists(id)`, `tokenState(id)` |
| Conformance | ERC-165, ERC-721, ERC-721 Metadata; safe-transfer receiver hook validated |
| Pause | Transfers, approvals, minting, and burning all freeze (see the caveat below) |

> **Operational caveat.** Pausing a collection also blocks transfers, which means an auction, raffle, or
> listing that escrows one of its tokens cannot settle while the collection is paused. Pause a live
> collection only with that consequence in mind.

---

## 8. Treasury

Contract: `src/core/Treasury.sol` · Tests: `test/treasury/`

| Capability | Guarantee |
| --- | --- |
| Credit an account | `authorizedPayer` only; increases `claimableBalance` and `totalLiabilities`; zero value rejected |
| Spend unencumbered funds | `pay()` requires `authorizedPayer`; bounded by `availableBalance()` so user liabilities can never be spent |
| Withdraw | Pull-based `withdrawClaimable()`; balance zeroed before transfer |
| Daily spending limit | Per-payer 24-hour window; `0` disables the limit |
| Fee recipient | `feeRecipientForProtocol()` is the destination for protocol fees credited by domains |
| Payer authorisation | Owner or `factoryController`; the Factory grants rights to contracts it creates that can legitimately spend |
| Emergency rescue | Owner only, bounded by `availableBalance()` |
| Solvency view | `availableBalance() = max(0, balance - totalLiabilities)` |
| Receiving | Plain ETH transfers accepted (needed for credits from domains) |

---

## 9. Payment Manager

Contract: `src/core/PaymentManager.sol` · Tests: `test/payment/`

| Capability | Guarantee |
| --- | --- |
| Credit an account | `authorizedCreditor` only |
| Withdraw | Pull-based `withdraw()`; balance zeroed before transfer |
| Creditor authorisation | Owner or `factoryController` |
| Claimable view | `claimable(account)` |
| Direct payments | Rejected — every wei entering is attributed to a named account |
| Purpose | Buyer-side refunds (offer cancellations, rejections, expiries), kept separate from protocol revenue |

---

## 10. Factory

Contract: `src/factory/ProtocolFactory.sol` · Tests: `test/factory/`

| Capability | Guarantee |
| --- | --- |
| Deploy a treasury | Ownership transferred to the caller |
| Deploy a payment manager | Ownership transferred to the caller |
| Deploy a marketplace | Caller must already control the target Treasury (owner or pending owner) |
| Deploy a custom NFT | Plain or CREATE2-deterministic |
| Predict an NFT address | `predictCustomNFTAddress(...)` |
| Deploy an open auction | Treasury controller check |
| Deploy a blind auction | Caller must be the beneficiary and own the NFT; NFT escrowed through the Factory |
| Deploy a dutch auction | Treasury controller check |
| Deploy staking | Caller must already control the Treasury |
| Deploy a raffle | Treasury controller check |
| Full suite | One call wires treasury, payment manager, marketplace proxy, open auction, dutch auction, and staking, then hands over ownership |
| Register instances | Every deployment is registered with its kind and implementation |
| Per-creator index | `creatorInstanceCount` / `creatorInstanceAt` |
| Finalise controllers | Owner-only; clears `factoryController` on both ledgers — irreversible by design |
| Transfer registry ownership | Re-registers the Factory as a registrar first, so discovery keeps working after the handoff |
| Salt uniqueness | CREATE2 salts are single-use per creator |

---

## 11. Registry

Contract: `src/registries/ProtocolRegistry.sol` · Tests: `test/registry/`

| Capability | Guarantee |
| --- | --- |
| Register an instance | Registrar only; rejects zero addresses, no-code instances, unknown versions, duplicates |
| Activate / deactivate | Owner only; inactive instances are skipped by discovery |
| Look up a record | Kind, creator, implementation, version, active flag |
| Global indexing | `allCount` / `allAt` |
| Per-kind indexing | `byKindCount` / `kindAt` |
| Per-creator indexing | `byCreatorCount` / `creatorAt` |
| Automation discovery | `automationInstances(kind, offset, limit)` |
| Cycle-aware discovery | `automationInstancesWithCycle(kind, offset, limit)` additionally returns `offset / count` so callers can drive rotating scans |

---

## 12. Governance

Contract: `src/governance/ProtocolGovernance.sol` · Tests: `test/governance/`

| Capability | Guarantee |
| --- | --- |
| Timelock control plane | `TimelockController` with a constructor-supplied minimum delay |
| Proposer / executor sets | Explicit at construction; an empty executor set means open execution after the delay |
| Bootstrap admin removal | `admin = address(0)` is the documented preference |
| Scheduled ownership acceptance | `ScheduleGovernanceOwnershipAcceptance.s.sol` batches the `acceptOwnership()` calls for every Timelock-owned contract |
| Executed ownership acceptance | `ExecuteGovernanceOwnershipAcceptance.s.sol` runs the batch after the delay |
| Marketplace governance | `ConfigureMarketplaceGovernance.s.sol` anchors `DEFAULT_ADMIN_ROLE` to the Timelock and assigns the operator role deliberately |

---

## 13. Chainlink CRE automation

Contracts: `src/automation/*` · Workflow: `cre/protocol-automation/` · Docs: [AUTOMATION.md](AUTOMATION.md)

| Capability | Guarantee |
| --- | --- |
| Scheduled discovery | Cron-driven workflow reads the registry and domain views every minute |
| Seven automated actions | Open/blind/dutch auction lifecycle, offer expiry, raffle winner request, raffle refund batches, failed-raffle finalisation |
| Explicit allowlist | The receiver has no `target.call(data)`; each action maps to exactly one function |
| Workflow identity | Report envelope must carry the configured workflow id **and** author |
| Kind validation | The registry record's kind must match the action's expected kind |
| Replay protection | `keccak256(action, instance, id, value, cursor)` can be processed once |
| Staleness bound | `scheduledAt` must be non-zero and no more than 10 minutes in the future |
| Refund cursor safety | Batch reports carry the expected on-chain cursor; a stale batch reverts |
| Bounded discovery | `(cycle, maxScan, maxItems)` caps iterations at 500 and results at 100 |
| Rotation and partitioning | `slot * partitionCount + partitionIndex` keeps every instance reachable |
| Read budget | 11 EVM reads per execution by default, under the documented 15-read quota |
| Gas budget | `gasLimit = 1,000,000`; refund batches of 12 measured at ~510k gas, 100 entries need ~3.1M and would not fit |
| Simulation isolation | A separate simulation receiver keeps production validation intact |
| Fail-closed | The receiver starts paused and cannot be unpaused without a configured workflow identity |

---

## 14. Verification and tooling

| Capability | Where |
| --- | --- |
| Domain-organised test suites | `test/<domain>/` — 84 `.t.sol` files, 638 test functions, 14 invariant functions |
| Fuzz and invariant profiles | `foundry.toml` default (`512` runs / `128 x 128`) and `ci` (`4096` runs / `512 x 256`) |
| Fork gate | `test/raffle/Raffle.Fork.t.sol` via `make fork` |
| Coverage measurement | `make coverage` |
| Gas snapshotting | `make snapshot` |
| Static analysis | `make lint` (`forge lint`, scope and exclusions in `foundry.toml`) |
| Mutation testing | `verification/mutation/` (Gambit) |
| Symbolic verification | `verification/symbolic/` (`solc --model-checker-engine all`) |
| Deployment tooling | 15 Foundry scripts under `script/` |
| Preflight gate | `make preflight` |
| Post-deployment verification | `make verify-deployment` |
| Dependency pinning | `script/install-dependencies.sh` + committed lockfile for the CRE workspace |
| Dependency monitoring | Dependabot for GitHub Actions and the CRE npm workspace |

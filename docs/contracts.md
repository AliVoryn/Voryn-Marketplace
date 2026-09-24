# Contract Reference

Reference for every contract in `src/`. Each entry documents state, external API, access gates, events,
errors, and invariants. Function tables mark visibility and the gate that protects the function.

> **Convention.** "Owner" = `owner()`. "Admin" = holder of `DEFAULT_ADMIN_ROLE`. "Timelock" = an instance
> of `ProtocolTimelock`. In a governance-controlled release they resolve to the same address.

## Index

| Contract | Path | Lines | Upgradeable |
| --- | --- | --- | --- |
| [Marketplace](#marketplace) | `src/core/Marketplace.sol` | 441 | Yes (UUPS) |
| [OpenAuction](#openauction) | `src/core/OpenAuction.sol` | 323 | No |
| [BlindAuction](#blindauction) | `src/core/BlindAuction.sol` | 329 | No |
| [DutchAuction](#dutchauction) | `src/core/DutchAuction.sol` | 189 | No |
| [Raffle](#raffle) | `src/core/Raffle.sol` | 435 | No |
| [Staking](#staking) | `src/core/Staking.sol` | 286 | No |
| [CustomNFT](#customnft) | `src/core/CustomNFT.sol` | 296 | No |
| [Treasury](#treasury) | `src/core/Treasury.sol` | 142 | No |
| [PaymentManager](#paymentmanager) | `src/core/PaymentManager.sol` | 58 | No |
| [ProtocolFactory](#protocolfactory) | `src/factory/ProtocolFactory.sol` | 327 | No |
| [ProtocolRegistry](#protocolregistry) | `src/registries/ProtocolRegistry.sol` | 134 | No |
| [ProtocolTimelock](#protocoltimelock) | `src/governance/ProtocolGovernance.sol` | 10 | No |
| [ProtocolAutomationReceiver](#protocolautomationreceiver) | `src/automation/ProtocolAutomationReceiver.sol` | 226 | No |
| [ProtocolAutomationSimulationReceiver](#protocolautomationsimulationreceiver) | `src/automation/ProtocolAutomationSimulationReceiver.sol` | 18 | No |
| [Libraries](#libraries) | `src/libraries/` | 221 | — |
| [Deployer libraries](#deployer-libraries) | `src/factory/deployers/` | 141 | — |

---

## Marketplace

`src/core/Marketplace.sol` — primary NFT marketplace: listings, offers, and EIP-712 signed orders.

**Inheritance:** `Initializable`, `UUPSUpgradeable`, `AccessControlUpgradeable`, `PausableUpgradeable`,
`EIP712Upgradeable`, `ReentrancyGuardUpgradeable`, `IMarketplace`

### Constants

| Constant | Value | Meaning |
| --- | --- | --- |
| `ADMIN_ROLE` | `keccak256("ADMIN_ROLE")` | Configuration: treasury, payment manager, fees |
| `OPERATOR_ROLE` | `keccak256("OPERATOR_ROLE")` | `pause` / `unpause` |
| `DEFAULT_LISTING_TTL` | `7 days` | Applied when `expiresAt == 0` |
| `DEFAULT_PROTOCOL_FEE_BPS` | `250` | 2.50% initial protocol fee |
| `DEFAULT_MINIMUM_FEE_BPS` | `100` | 1.00% initial floor |
| `MAX_BATCH_CANCEL` | `50` | Upper bound on `cancelListings` |
| `LISTING_TYPEHASH` | `ListingOrder(address seller,address nft,uint256 tokenId,uint256 price,uint64 expiresAt,uint256 nonce)` | EIP-712 struct hash |

### State

| Variable | Type | Notes |
| --- | --- | --- |
| `treasury` | `address` | Must return `true` from `authorizedPayer(address(this))` when set |
| `paymentManager` | `address` | Must return `true` from `authorizedCreditor(address(this))` when set |
| `protocolFeeBps` | `uint16` | ≤ 1000 |
| `minimumFeeBps` | `uint16` | ≤ 1000; effective fee is `max(protocol, minimum)` |
| `totalOfferEscrow` | `uint256` | Public liability counter |
| `orderNonce` | `mapping(address => uint256)` | Public; consumed by signed orders |
| `customFeeBps` / `customFeeEnabled` | `mapping(address => …)` | Public per-account fee override |

Private state: `nextListingId`, `nextOfferId`, `listings`, `offers`, `sellerListings`, `buyerOffers`.

### External API

| Function | Visibility | Gate | Purpose |
| --- | --- | --- | --- |
| `initialize(admin, treasury_, paymentManager_)` | public | `initializer` | Grants `DEFAULT_ADMIN_ROLE`, `ADMIN_ROLE`, `OPERATOR_ROLE`; sets `EIP712("Professional Marketplace", "1")`; requires both dependencies to have code |
| `createListing(nft, tokenId, price, expiresAt)` | external | `whenNotPaused` | Requires caller to own `tokenId`; `expiresAt == 0` → `block.timestamp + 7 days` |
| `updateListing(listingId, newPrice, newExpiresAt)` | external | `whenNotPaused` | Seller only; re-verifies NFT ownership |
| `cancelListing(listingId)` | external | `whenNotPaused` | Seller only; reverts if already stale |
| `cancelListings(listingIds[])` | external | `whenNotPaused` | Batch, `1..50`; reverts entirely on first failure |
| `expireListing(listingId)` | external | `whenNotPaused` | Permissionless once past `expiresAt` |
| `buy(listingId)` | external payable | `nonReentrant whenNotPaused` | Exact payment; splits fee; credits treasury and seller; transfers NFT; `msg.sender != seller` |
| `makeOffer(nft, tokenId, expiresAt)` | external payable | `whenNotPaused` | Escrows `msg.value`; `expiresAt` must be in the future; increments `totalOfferEscrow` |
| `cancelOffer(offerId)` | external | `nonReentrant whenNotPaused` | Buyer only; refund via `PaymentManager` |
| `expireOffer(offerId)` | external | `nonReentrant whenNotPaused` | Permissionless after expiry; refund via `PaymentManager` |
| `acceptOffer(offerId)` | external | `nonReentrant whenNotPaused` | Requires caller to own the offered token; splits fee; transfers NFT |
| `rejectOffer(offerId)` | external | `nonReentrant whenNotPaused` | Token owner only; refunds buyer |
| `executeSignedListing(...)` | external payable | `nonReentrant whenNotPaused` | EIP-712 order; nonce must equal `orderNonce[seller]`; increments the nonce |
| `hashListingOrder(...)` | external view | — | Off-chain order hash helper |
| `invalidateNonce()` | external | — | Bumps `orderNonce[msg.sender]`, cancelling all outstanding orders |
| `setTreasury(treasury_)` | external | `onlyRole(ADMIN_ROLE)` | Rejects a treasury that has not authorised this contract as payer |
| `setPaymentManager(paymentManager_)` | external | `onlyRole(ADMIN_ROLE)` | Rejects a manager that has not authorised this contract as creditor |
| `setProtocolFee(bps)` / `setMinimumFeeBps(bps)` | external | `onlyRole(ADMIN_ROLE)` | ≤ 1000 |
| `setCustomFee(account, bps, active)` | external | `onlyRole(ADMIN_ROLE)` | ≤ 1000 |
| `pause()` / `unpause()` | external | `onlyRole(OPERATOR_ROLE)` | — |
| `getListing`, `getOffer`, `listingCount`, `offerCount`, `nonceOf`, `domainInfo`, `version` | external view | — | Read surface |
| `sellerListingCount` / `sellerListingAt`, `buyerOfferCount` / `buyerOfferAt` | external view | — | Enumeration helpers |
| `automationDueOfferIds(cycle, maxScan, maxItems)` | external view | returns `[]` when paused | Bounded discovery of expired offers |

### Invariants

| Invariant | Checked by |
| --- | --- |
| `address(this).balance >= totalOfferEscrow` | `_assertOfferEscrow()` after `makeOffer`, `acceptOffer`, and every refund path |
| Effective fee is never below `minimumFeeBps` unless a custom fee is enabled for that seller | `_effectiveFeeBps` |
| A listing can only settle while the seller still owns the token | `_requireActiveListing`, `_settleSignedListing` |

### Notes

- Fee routing is asymmetric by design: the *fee* is credited to `Treasury.feeRecipientForProtocol()`,
  while *proceeds* are credited to the seller's own claimable balance.
- Offer escrow lives in the Marketplace's balance but the refund path pushes value into
  `PaymentManager.credit`, so the Marketplace is the only contract holding buyer money between the offer
  and its resolution.

---

## OpenAuction

`src/core/OpenAuction.sol` — English auction with reserve price, minimum increment, anti-sniping extension,
and optional buyout.

**Inheritance:** `Ownable2Step`, `ReentrancyGuard`, `Pausable`, `IAuction`

### Immutables and state

| Variable | Type | Notes |
| --- | --- | --- |
| `treasury` | `address immutable` | Must have code |
| `protocolFeeBps` | `uint16 immutable` | ≤ 1000 |
| `nextAuctionId` | `uint256` | Starts at 1 |
| `totalActiveBidLiability` | `uint256` | Public |
| `totalRefundLiability` | `uint256` | Public |

Defaults applied in `createAuction`: `extensionWindow = 5 minutes`, `extensionTime = 5 minutes`,
`maxExtensions = 3`.

### Phases

`Created → Scheduled → Active → Ended → Finalizable → Finalized`, plus `Failed` and `Cancelled`.

`_activateIfReady` promotes `Created`/`Scheduled` to `Active` on first interaction after `startAt`, so a
bidder never needs a separate activation transaction.

### External API

| Function | Gate | Notes |
| --- | --- | --- |
| `createAuction(nft, tokenId, reservePrice, minIncrement, startAt, duration)` | `nonReentrant whenNotPaused` | Escrows the NFT; requires caller ownership |
| `startAuction(auctionId)` | `whenNotPaused` | Seller only, inside the schedule window |
| `configureBuyout(auctionId, price)` | `sellerOrOwner` | `price > reservePrice`; only before `endAt` |
| `placeBid(auctionId)` | `nonReentrant whenNotPaused` | ≥ `max(reservePrice, highestBid + minIncrement)`; seller excluded; extends in the final 5 minutes up to 3 times |
| `buyout(auctionId)` | `nonReentrant whenNotPaused` | Exact `buyoutPrice`; refunds the standing highest bidder; immediately finalises |
| `endAuction(auctionId)` | `whenNotPaused` | Permissionless after `endAt`; moves `Active → Ended` |
| `cancelAuction(auctionId)` | `sellerOrOwner nonReentrant` | Only before `endAt`; refunds the highest bidder; returns the NFT |
| `finalizeAuction(auctionId)` | `nonReentrant whenNotPaused` | Settles winner or fails the auction and returns the NFT |
| `withdrawRefund()` | `nonReentrant` | Pull-based refund claim |
| `pause()` / `unpause()` | `onlyOwner` | — |
| `automationDueIds(cycle, maxScan, maxItems)` | view | Returns auctions past `endAt` in a non-terminal phase |

### Invariants

```text
address(this).balance >= totalActiveBidLiability + totalRefundLiability
```

Enforced by `_assertEscrowInvariant()` after `finalizeAuction`, `buyout`, `cancelAuction`, and refund
credits. `receive()` reverts with `DirectPaymentNotAllowed()`, so ETH can only enter through `placeBid`
and `buyout`.

---

## BlindAuction

`src/core/BlindAuction.sol` — sealed-bid commit/reveal auction. One contract per NFT.

**Inheritance:** `IBlindAuction`, `Ownable2Step`, `Pausable`, `ReentrancyGuard`

### Design

- The NFT is transferred into the contract by the Factory at creation
  (`ProtocolFactory.createBlindAuctionInstance` escrows it before deploying).
- Commitments are `keccak256(abi.encodePacked(value, fake, secret))`.
- `commitmentUsed[hash]` makes every commitment single-use, which removes the classic
  "replay someone else's commitment" front-running vector.

### Constants

| Constant | Value |
| --- | --- |
| `MAX_BIDS_PER_ADDRESS` | `20` |
| `REVEAL_EXTENSION_WINDOW` | `5 minutes` |
| `REVEAL_EXTENSION_TIME` | `5 minutes` |
| `MAX_REVEAL_EXTENSIONS` | `3` |

### Phases

`Bidding → Reveal → AwaitingFinalization → Ended`, plus `Cancelled`.
Phase is derived from the clock in `AuctionPhaseLib.currentPhase`, so it is always consistent with
`block.timestamp`.

### External API

| Function | Gate | Notes |
| --- | --- | --- |
| `placeBid(blindedBid)` | `whenNotPaused onlyInPhase(Bidding)` | Escrows `msg.value` as deposit; rejects the beneficiary; enforces `MAX_BIDS_PER_ADDRESS` and single-use commitments |
| `computeBlindedBid(value, fake, secret)` | pure | Canonical commitment helper |
| `reveal(values[], fakes[], secrets[])` | `nonReentrant whenNotPaused onlyInPhase(Reveal)` | Lengths must equal the caller's bid count; credits refunds; a valid reveal can extend the reveal window |
| `finalizeAuction()` | `nonReentrant whenNotPaused onlyInPhase(AwaitingFinalization)` | Reserve-met → NFT to winner and proceeds to seller; otherwise NFT to beneficiary and best bid to `pendingReturns` |
| `withdraw()` | `nonReentrant` | Pull-based withdrawal of `pendingReturns` |
| `withdrawUnrevealed()` | `nonReentrant` | Reclaims deposits for commitments never revealed; available from `AwaitingFinalization` onward |
| `withdrawIfCancelled()` | `nonReentrant onlyInPhase(Cancelled)` | Combines unrevealed deposits and pending returns in one withdrawal |
| `cancelAuction()` | `onlyOwner` | Only during `Bidding` or `Reveal`; returns the NFT to the beneficiary |
| `pause()` / `unpause()` | `onlyOwner` | — |
| `automationReady()` | view | `!paused() && currentPhase() == AwaitingFinalization` |

### Invariants

```text
address(this).balance >= totalPendingReturns + totalUnrevealedDeposits (+ highestBid while open)
```

`_assertEscrowInvariant()` runs after finalisation, cancellation, and each withdrawal path.

### Known limitation

`ProtocolFactory.createBlindAuctionInstance` calls `Treasury.setAuthorizedPayer(instance, true)`. Once the
Factory controller has been finalised to `address(0)`, this call reverts. See
[security.md](security.md#known-design-limitations).

---

## DutchAuction

`src/core/DutchAuction.sol` — declining-price auction. One contract hosts many auctions.

**Inheritance:** `Ownable2Step`, `ReentrancyGuard`, `Pausable`, `IDutchAuction`

### Price model

```text
if now <= startAt   -> startPrice
if now >= endAt     -> endPrice
otherwise           -> startPrice - (startPrice - endPrice) * (now - startAt) / (endAt - startAt)
```

Computed with `Math.mulDiv`, so it is exact for the full `uint256` range.

### External API

| Function | Gate | Notes |
| --- | --- | --- |
| `createAuction(nft, tokenId, startPrice, endPrice, startAt, duration)` | `nonReentrant whenNotPaused` | Requires `startPrice > endPrice` and caller ownership; escrows the NFT |
| `buy(auctionId)` | `nonReentrant whenNotPaused` | Requires `msg.value >= currentPrice`; refunds the excess inline; seller cannot buy |
| `cancelAuction(auctionId)` | `nonReentrant whenNotPaused` | Seller or owner; only before `endAt` |
| `expireAuction(auctionId)` | `nonReentrant whenNotPaused` | Permissionless after `endAt`; returns NFT to seller |
| `currentPrice(auctionId)` | view | Reverts for unknown ids |
| `automationDueIds(cycle, maxScan, maxItems)` | view | Auctions past `endAt` still in `Created`/`Active` |
| `pause()` / `unpause()` | `onlyOwner` | — |

### Notes

- `excess` is refunded with a direct `call` to `msg.sender` (not a third party), so a failing receiver
  only reverts that buyer's own purchase.
- DutchAuction has **no escrow accounting** — it never holds value across transactions. Only the NFT is
  escrowed, so there is no balance invariant to assert.

---

## Raffle

`src/core/Raffle.sol` — ticket raffle with Chainlink VRF V2.5 winner selection.

**Inheritance:** `Ownable2Step`, `ReentrancyGuard`, `Pausable`, `IRaffle`

### Constants

| Constant | Value | Meaning |
| --- | --- | --- |
| `MAX_FEE_BPS` | `1000` | Hard ceiling on the raffle fee |
| `RANDOMNESS_RETRY_DELAY` | `1 hours` | Cooldown before `retryRandomWinnerRequest` |
| `STUCK_RAFFLE_CANCEL_DELAY` | `24 hours` | Delay before a stuck raffle can be cancelled |
| `MAX_REFUND_BATCH` | `100` | Ceiling for `processRaffleRefunds` |

### Phases

`Created → Active → AwaitingRandomness → Finalized`, plus `Cancelled` and `Failed`.

### VRF configuration

Two constructor/`setVRFConfig` validation rules apply everywhere, including at construction:
`requestConfirmations` must be in `[3, 200]`, and the coordinator must have code, a non-zero
subscription id, a non-zero key hash, and a non-zero callback gas limit. The repository default callback
gas limit is `500000` (see [`raffle-mainnet.md`](raffle-mainnet.md) for the measurement procedure).

### External API

| Function | Gate | Notes |
| --- | --- | --- |
| `createRaffle(nft, tokenId, ticketPrice, maxTickets, maxTicketsPerWallet, startAt, duration)` | `nonReentrant whenNotPaused` | Escrows the NFT; `maxTickets` capped at `type(uint128).max` |
| `buyTickets(raffleId, quantity)` | `nonReentrant whenNotPaused` | Enforces per-wallet cap and total cap; records a single `Entrant` span per purchase |
| `requestRandomWinner(raffleId)` | `nonReentrant whenNotPaused` | Permissionless once sold out or past `endAt`; calls the coordinator |
| `retryRandomWinnerRequest(raffleId)` | `onlyOwner nonReentrant` | Privileged recovery after `RANDOMNESS_RETRY_DELAY`; deliberately **not** in the automation allowlist |
| `cancelStuckRaffle(raffleId)` | `nonReentrant` | Creator only, after `STUCK_RAFFLE_CANCEL_DELAY` in `AwaitingRandomness` |
| `processRaffleRefunds(raffleId, maxEntries)` | `nonReentrant` | Cursor-based batching over entrants; `1..100` entries per call |
| `claimRaffleRefund()` | `nonReentrant` | Pull-based claim of accumulated refund credit |
| `finalizeFailedRaffle(raffleId)` | `nonReentrant` | Zero-ticket raffle after `endAt`; returns NFT to creator |
| `cancelRaffle(raffleId)` | `nonReentrant` | Creator or owner; only with zero tickets sold |
| `setFeeBps(bps)` | `onlyOwner` | ≤ 1000 |
| `setVRFConfig(...)` | `onlyOwner` | Full re-validation on every change |
| `pause()` / `unpause()` | `onlyOwner` | — |
| `rawFulfillRandomWords(requestId, randomWords[])` | `nonReentrant` | VRF callback; see below |
| `automationCandidates(cycle, maxScan, maxItems)` | view | Returns `(winnerRequestIds, failedIds, refundCandidates)` |

### The VRF callback

`rawFulfillRandomWords` is the only externally callable entry point that is not user-initiated. Its
validation order is deliberate:

```text
1. requestIdToCoordinator[requestId] != 0 and requestIdToRaffleId[requestId] != 0
2. msg.sender == requestIdToCoordinator[requestId]
3. randomWords.length == 1
4. raffle.phase == AwaitingRandomness and raffle.vrfRequestId == requestId
5. clear the request mappings
6. compute the winning index, resolve the entrant, split proceeds, transfer the NFT
7. _assertInvariant()
```

Steps 1–4 happen before any state write. Because the callback finalises inside the VRF fulfillment, the
configured callback gas limit must be comfortably above the measured fulfillment cost — if it runs out of
gas, the coordinator does not retry and the raffle stays in `AwaitingRandomness` until the stuck-raffle
path is used.

### Invariants

```text
address(this).balance >= totalActiveRaffleFunds + totalRaffleRefundLiability
```

---

## Staking

`src/core/Staking.sol` — reward staking with a scheduled reward program and account cooldowns.

**Inheritance:** `Ownable2Step`, `Pausable`, `ReentrancyGuard`, `IStaking`

### Constants and defaults

| Item | Value |
| --- | --- |
| `ACC_SCALE` | `1e18` (reward-per-token accumulator precision) |
| `MAX_REWARD_RATE` | `1e24` per second of scaled accumulator growth |
| `minimumStake` | `0.01 ether` at construction |
| `unstakeCooldown` | `1 days` |
| `emergencyPenaltyBps` | `1000` (10%) |

### Reward accounting

The contract keeps two parallel views of a position: a public `Position` struct (`amount`, `rewardDebt`,
`lastAction`, `active`) and a private `UserAccounting` struct (`amount`, `rewards`, `rewardPerTokenPaid`,
`cooldownEndsAt`, `active`). The internal accounting is authoritative; the public struct is the
integrator-facing projection.

Accrual follows the accumulator pattern:

```text
rewardPerTokenStored += rewardRate * elapsed * ACC_SCALE / totalStaked
user.rewards += user.amount * (rewardPerTokenStored - user.rewardPerTokenPaid) / ACC_SCALE
user.rewardPerTokenPaid = rewardPerTokenStored
```

`scheduleRewardProgram` requires `rewardAmount` to be **exactly divisible** by the program duration, which
is why the corresponding `forge lint` finding (`divide-before-multiply`) is a documented false positive:
the division is exact by construction.

### External API

| Function | Gate | Notes |
| --- | --- | --- |
| `fundRewards()` | payable | Adds to `rewardReserve` |
| `fundRewardsFromTreasury(amount)` | `onlyOwner` | Pulls via `Treasury.pay` with reason `STAKING_REWARD_FUNDING` |
| `scheduleRewardProgram(startAt, endAt, rewardAmount)` | payable `onlyOwner` | Requires no active or scheduled program; validates divisibility and inventory |
| `stake()` | payable `nonReentrant whenNotPaused` | Enforces `minimumStake` / `maximumStake`; refreshes cooldown |
| `unstake(amount)` | `nonReentrant whenNotPaused` | Cooldown must have elapsed |
| `claimReward()` | `nonReentrant` | Reverts with `InsufficientRewardInventory` if the payout is not covered |
| `compoundReward()` | `nonReentrant whenNotPaused` | Converts rewards into stake; refreshes cooldown |
| `emergencyUnstake()` | `nonReentrant` | Forfeits accrued rewards and applies `emergencyPenaltyBps`; the penalty stays in the contract and remains part of the available inventory |
| `configureBounds(minimum, maximum)` | `onlyOwner` | `maximum == 0` means unbounded |
| `setCooldown(cooldown)` / `setEmergencyPenalty(bps)` | `onlyOwner` | — |
| `pause()` / `unpause()` | `onlyOwner` | — |
| `pendingReward(account)` / `getPosition(account)` / `rewardInventory()` / `currentRewardPhase()` | view | — |

### Invariant

```text
address(this).balance >= totalStaked + totalRewardLiability + rewardReserve
```

`rewardInventory()` is exactly `balance - (totalStaked + totalRewardLiability + rewardReserve)`. The
contract has no direct-payment rejection: `claimReward` and `unstake` use `call`, and the emergency
penalty increases the surplus rather than creating a liability.

---

## CustomNFT

`src/core/CustomNFT.sol` — self-contained ERC-721 implementation with roles, mint windows, and wallet
limits.

**Inheritance:** `AccessControl`, `Pausable`, `ReentrancyGuard`, `ICustomNFT`

### Roles

| Role | Purpose |
| --- | --- |
| `DEFAULT_ADMIN_ROLE` | Role administration, `setMintWindow`, `setWalletMintLimit`, minter grant/revoke |
| `MINTER_ROLE` | `mint`, `mintBatch` |
| `OPERATOR_ROLE` | `pause`, `unpause` |
| `METADATA_ROLE` | `setTokenURI`, `setBaseURI` |

### Constants

| Constant | Value |
| --- | --- |
| `MAX_BATCH_MINT` | `100` |

`maxSupply` is `immutable`. `maxSupply == 0` means unlimited.

### Mint phases

`currentMintPhase()` returns `Active` when both bounds are zero, `Scheduled` before `mintStartAt`,
`Ended` at or after `mintEndAt`, and `Active` otherwise.

### External API

| Function | Gate |
| --- | --- |
| `mint(to, tokenURI_)` | `onlyRole(MINTER_ROLE) whenNotPaused` + active mint phase |
| `mintBatch(to, tokenURIs[])` | `onlyRole(MINTER_ROLE) whenNotPaused` + active phase; `1..100` entries |
| `burn(tokenId)` | `whenNotPaused`; owner or approved |
| `transferFrom` / `safeTransferFrom` (both overloads) | `whenNotPaused`; `safeTransferFrom` adds `nonReentrant` |
| `approve` / `revokeApproval` / `setApprovalForAll` | `whenNotPaused` |
| `setMintWindow(startAt, endAt)` | `onlyRole(DEFAULT_ADMIN_ROLE)` |
| `setWalletMintLimit(limit)` | `onlyRole(DEFAULT_ADMIN_ROLE)` |
| `setTokenURI(tokenId, uri)` / `setBaseURI(uri)` | `onlyRole(METADATA_ROLE)` |
| `grantMinter` / `revokeMinter` | `onlyRole(DEFAULT_ADMIN_ROLE)` |
| `pause` / `unpause` | `onlyRole(OPERATOR_ROLE)` |
| `ownerOf`, `balanceOf`, `getApproved`, `isApprovedForAll` | view |
| `exists`, `tokenState`, `tokenURI`, `totalSupply`, `maxSupply`, `tokensOfOwner`, `walletMinted` | view |
| `currentMintPhase`, `mintWindow` | view |
| `supportsInterface` | view |

Enumeration helpers worth noting: `tokensOfOwner(owner)` returns the full id list for an owner, and
`walletMinted(owner)` returns how many tokens that wallet has ever minted — the value checked against
`walletMintLimit`.

### Conformance

`supportsInterface` reports ERC-165, ERC-721, and ERC-721 Metadata. An ERC-721 receiver hook that returns
the wrong selector reverts with `InvalidReceiver`. Behaviour is verified against an independent
conformance suite; see [test-matrix.md](test-matrix.md).

### Notes

- Minting emits both `Minted` and the ERC-721 `Transfer(address(0), to, tokenId)`.
- Pausability is transfer-level as well as mint-level: a paused collection freezes transfers, which is a
  deliberate operational lever with consequences for live listings and auctions. See
  [security.md](security.md).

---

## Treasury

`src/core/Treasury.sol` — liability ledger and controlled payment rail.

**Inheritance:** `Ownable2Step`, `ReentrancyGuard`, `ITreasury`

### State

| Variable | Type | Notes |
| --- | --- | --- |
| `totalLiabilities` | `uint256` | Public sum of all claimable balances |
| `feeRecipient` | `address` | Receives protocol fees credited by domains |
| `factoryController` | `address` | Allowed to grant payer rights; finalisable to `address(0)` |
| `authorizedPayer` | `mapping(address => bool)` | Public |

### External API

| Function | Gate | Notes |
| --- | --- | --- |
| `credit(account, reason)` | payable `onlyAuthorizedPayer` | Increases `claimableBalance[account]` and `totalLiabilities`; rejects zero value |
| `pay(recipient, amount, reason)` | `onlyAuthorizedPayer nonReentrant` | Spends **unencumbered** funds only (`amount <= availableBalance()`); consumes the daily allowance |
| `withdrawClaimable()` | `nonReentrant` | Pull-based claim; zeroes the balance before transferring |
| `setAuthorizedPayer(payer, allowed)` | owner **or** `factoryController` | — |
| `setFactoryController(controller)` | `onlyOwner` | — |
| `setFeeRecipient(recipient)` | `onlyOwner` | — |
| `setSpendingLimit(payer, dailyLimit)` | `onlyOwner` | `0` disables the limit |
| `spendingLimitOf(payer)` / `remainingDailyAllowance(payer)` | view | Window rolls every 24h |
| `availableBalance()` | view | `balance - totalLiabilities`, floored at zero |
| `emergencyRescue(recipient, amount)` | `onlyOwner nonReentrant` | ≤ `availableBalance()`; cannot touch user liabilities |

### Invariant

```text
claimable balances never exceed the contract balance minus what has been spent
availableBalance() >= 0
```

The rescue path is bounded by `availableBalance()`, which makes it structurally impossible for the owner
to drain user liabilities through it.

---

## PaymentManager

`src/core/PaymentManager.sol` — second ledger, used for buyer-side refunds.

**Inheritance:** `Ownable2Step`, `ReentrancyGuard`, `IPaymentManager`

| Function | Gate | Notes |
| --- | --- | --- |
| `credit(account, reason)` | payable `onlyCreditor` | Increases `claimableBalance` and `totalClaimable` |
| `withdraw()` | `nonReentrant` | Pull-based claim |
| `setCreditor(creditor, authorized)` | owner **or** `factoryController` | — |
| `setFactoryController(controller)` | `onlyOwner` | — |
| `claimable(account)` | view | — |

`receive()` reverts with `DirectPaymentNotAllowed()`, so value can only arrive through `credit` — which
means every wei that enters is attributed to a named account.

**Why two ledgers?** Marketplace *proceeds* are seller revenue and flow through the Treasury, alongside
protocol fees. Marketplace *offer refunds* are buyer money returning to its owner; routing them through a
separate ledger keeps revenue accounting and reversal accounting from being mixed in the same balance.
The separation is enforced structurally: the Marketplace must be an authorised payer of the Treasury and
an authorised creditor of the PaymentManager, and both facts are re-validated whenever an admin changes a
dependency.

---

## ProtocolFactory

`src/factory/ProtocolFactory.sol` — deployment, wiring, and registry registration.

**Inheritance:** `Ownable2Step`, `ReentrancyGuard`, `IFactory`

### Kinds

`KIND_MARKETPLACE`, `KIND_NFT`, `KIND_OPEN_AUCTION`, `KIND_BLIND_AUCTION`, `KIND_DUTCH_AUCTION`,
`KIND_STAKING`, `KIND_RAFFLE`, `KIND_TREASURY`, `KIND_PAYMENT_MANAGER` — each
`keccak256(<NAME>)`.

### Constructor

Deploys the `ProtocolRegistry` (owned by the Factory) and the single `Marketplace` implementation used by
every proxy. Emits `RegistryReferenceSet`.

### External API

| Function | Gate | Authority rule |
| --- | --- | --- |
| `createTreasury(feeRecipient)` | — | Transfers ownership to the caller |
| `createPaymentManager()` | — | Transfers ownership to the caller |
| `createMarketplace(admin, treasury, paymentManager)` | `nonReentrant` | Both ledgers must be Factory-controlled **and** the caller must be Treasury owner or pending owner |
| `createCustomNFT(name, symbol, maxSupply, admin)` | — | — |
| `createCustomNFTDeterministic(..., salt)` | `nonReentrant` | Salt is per-creator single-use |
| `predictCustomNFTAddress(...)` | view | CREATE2 prediction |
| `createAuctionInstance(treasury)` | `nonReentrant` | Treasury controller check only |
| `createBlindAuctionInstance(...)` | `nonReentrant` | Caller must be the beneficiary and own the NFT; NFT escrowed via the Factory |
| `createDutchAuctionInstance(owner, treasury, feeBps)` | `nonReentrant` | Treasury controller check only |
| `createStaking(rewardTreasury)` | `nonReentrant` | Caller must be Treasury owner or pending owner |
| `createRaffleInstance(...)` | `nonReentrant` | Treasury controller check only |
| `createProtocolSuite(admin, feeRecipient)` | `nonReentrant` | Returns the full wiring; transfers Treasury and PaymentManager ownership to `admin` |
| `finalizeProtocolSuiteControllers(treasury, paymentManager)` | `onlyOwner` | Sets both `factoryController` values to `address(0)` — irreversible |
| `transferRegistryOwnership(newOwner)` | `onlyOwner` | Re-registers the Factory as a registrar, then transfers the registry |
| `creatorInstanceCount` / `creatorInstanceAt` | view | Per-creator enumeration |

### `createProtocolSuite` wiring

```text
1. CoreDeployer.deployTreasury(factory, feeRecipient, factory)
2. CoreDeployer.deployPaymentManager(factory, factory)
3. CoreDeployer.deployProxy(marketplaceImplementation, initialize(admin, treasury, paymentManager))
4. AuctionDeployer.deployOpen(admin, treasury, 250)
5. AuctionDeployer.deployDutch(admin, treasury, 250)
6. StakingDeployer.deploy(admin, treasury)
7. Treasury.setAuthorizedPayer(marketplace | auction | dutchAuction | staking, true)
8. PaymentManager.setCreditor(marketplace, true)
9. Treasury.transferOwnership(admin)
10. PaymentManager.transferOwnership(admin)
11. Register all six instances
```

Step 9 and 10 start a two-step handoff: the new owner must call `acceptOwnership()`. Until then the
Factory remains a legitimate `pendingOwner`, which is why `_requireTreasuryAuthority` accepts either the
current or the pending owner.

### Deterministic NFT addresses

`createCustomNFTDeterministic` namespaces the caller-supplied salt before using it:

```solidity
bytes32 namespacedSalt = keccak256(abi.encode(msg.sender, salt));
instance = NFTDeployer.deployDeterministic(name_, symbol_, maxSupply_, admin, namespacedSalt);
```

and `predictCustomNFTAddress` applies the identical transformation, so a predicted address is only valid
for the `(creator, salt, constructor-arguments)` tuple it was computed from. Using `abi.encode` (not
`encodePacked`) makes the namespacing unambiguous for dynamic argument types.

### Errors specific to the Factory

`UnauthorizedTreasuryController`, `UnauthorizedPaymentManagerController`, `NotTreasuryAuthority`,
`SaltAlreadyUsed`, `NotSeller`, `InvalidContract`, `ZeroAddress`.

---

## ProtocolRegistry

`src/registries/ProtocolRegistry.sol` — instance records and the discovery surface for automation.

**Inheritance:** `Ownable2Step`, `IRegistry`

### Record

```solidity
struct Record {
    address instance;
    address implementation;
    address creator;
    bytes32 kind;
    uint64  version;
    bool    active;
}
```

### External API

| Function | Gate | Notes |
| --- | --- | --- |
| `registerInstance(instance, creator, implementation, kind, version)` | `onlyRegistrar` | Rejects zero addresses, no-code instances, unknown versions, and duplicates |
| `setRegistrar(account, allowed)` | `onlyOwner` | — |
| `setActive(instance, active)` | `onlyOwner` | Soft disable; automation skips inactive instances |
| `getRecord(instance)` | view | Reverts `UnknownInstance` if absent |
| `isRegistered(instance)` | view | — |
| `allCount` / `allAt`, `byKindCount` / `kindAt`, `byCreatorCount` / `creatorAt` | view | Indexed enumeration |
| `automationInstances(kind, offset, limit)` | view | Address list only |
| `automationInstancesWithCycle(kind, offset, limit)` | view | Adds the derived `cycle` = `offset / count` |

`automationInstancesWithCycle` maps an arbitrary global offset onto the kind's ring, filtering out
inactive records, and returns the window along with the cycle count so an off-chain workflow can pass a
monotonically increasing `cycle` to the domain scan functions.

---

## ProtocolTimelock

`src/governance/ProtocolGovernance.sol` — a thin, opinionated subclass of OpenZeppelin's
`TimelockController`.

```solidity
constructor(uint256 minDelay, address[] proposers, address[] executors, address admin)
```

No behaviour is added or removed. The value of the contract is that it fixes a single governance
primitive for the protocol: a minimum delay, an explicit proposer set, an explicit executor set (or open
execution after the delay), and an optional bootstrap admin that should be `address(0)` for a
no-bootstrap release.

`docs/mainnet.md` prefers `GOVERNANCE_ADMIN=0x000…0` so the protocol does not retain a privileged
bootstrap account after setup.

---

## ProtocolAutomationReceiver

`src/automation/ProtocolAutomationReceiver.sol` — fail-closed on-chain boundary for CRE reports.

**Inheritance:** `ReceiverTemplate`, `Ownable2Step`, `Pausable`

### Action allowlist

| # | Action | Target function | Expected registry kind |
| --- | --- | --- | --- |
| 0 | `FINALIZE_OPEN_AUCTION` | `IAuction.finalizeAuction(uint256)` | `OPEN_AUCTION` |
| 1 | `FINALIZE_BLIND_AUCTION` | `IBlindAuction.finalizeAuction()` | `BLIND_AUCTION` |
| 2 | `EXPIRE_DUTCH_AUCTION` | `IDutchAuction.expireAuction(uint256)` | `DUTCH_AUCTION` |
| 3 | `EXPIRE_OFFER` | `IMarketplace.expireOffer(uint256)` | `MARKETPLACE` |
| 4 | `REQUEST_RAFFLE_WINNER` | `IRaffle.requestRandomWinner(uint256)` | `RAFFLE` |
| 5 | `PROCESS_RAFFLE_REFUNDS` | `IRaffle.processRaffleRefunds(uint256,uint256)` | `RAFFLE` |
| 6 | `FINALIZE_FAILED_RAFFLE` | `IRaffle.finalizeFailedRaffle(uint256)` | `RAFFLE` |

`Raffle.retryRandomWinnerRequest` is deliberately **excluded** — it is owner-only privileged recovery, not
a trust-minimised action.

### Report layout

Reports are exactly 224 bytes and decode as:

```solidity
(uint8 action, address instance, uint256 id, uint256 value, uint256 cursor, uint64 scheduledAt, uint64 chainSelector)
```

The Chainlink envelope additionally carries `workflowId | name(10) | owner(20) | reportId(2)`.

### Constants

| Constant | Value |
| --- | --- |
| `MAX_REFUND_BATCH` | `100` |
| `MAX_FUTURE_SKEW` | `10 minutes` |

### Validation order in `_processReport`

```text
1.  !paused()
2.  msg.sender == this.getForwarderAddress() and forwarder != 0
3.  workflow id AND author configured
4.  report.length == 224
5.  decode; actionRaw <= FINALIZE_FAILED_RAFFLE
6.  _validate(request)
7.  replayKey = keccak256(action, instance, id, value, cursor) not already processed
8.  mark processed
9.  dispatch through the if/else allowlist
10. emit AutomationActionExecuted
```

### `_validate` rules

- Instance is non-zero and has code.
- `chainSelector == expectedChainSelector`.
- `scheduledAt != 0` and `scheduledAt <= block.timestamp + MAX_FUTURE_SKEW`.
- Registry record exists and `record.active == true`.
- `record.kind` equals the kind implied by the action.
- `FINALIZE_BLIND_AUCTION` requires `id == 0`.
- `PROCESS_RAFFLE_REFUNDS` requires `id != 0`, `1 <= value <= 100`, and
  `Raffle.refundCursor(id) == cursor`.
- All other actions require `id != 0` (except blind), `value == 0`, and `cursor == 0`.

### Fail-closed guarantees

- The constructor calls `_pause()`, so the receiver is inert until an operator configures and unpauses it.
- `unpauseAutomation()` reverts unless both the workflow id and author are set.
- Clearing either value later makes `_processReport` revert with `WorkflowNotConfigured`.

---

## ProtocolAutomationSimulationReceiver

`src/automation/ProtocolAutomationSimulationReceiver.sol` — a strict subclass that overrides
`_requiresWorkflowIdentity()` to return `false`.

Purpose: `cre workflow simulate` delivers reports through a `MockForwarder` that carries no workflow
metadata. Rather than weakening the production receiver, simulation uses this separate contract. It
exposes `isSimulationReceiver() == true` so deployment scripts can detect and reject it outside testnets.

**Do not deploy this on mainnet.** `DeployAutomationSimulationReceiver.s.sol` enforces the known-testnet
list: Sepolia (11155111), Base Sepolia (84532), Arbitrum Sepolia (421614), Optimism Sepolia (11155420),
Polygon Amoy (80002), Avalanche Fuji (43113), BNB Testnet (97).

---

## Libraries

| Library | File | API | Purpose |
| --- | --- | --- | --- |
| `AccountingMath` | `AccountingMath.sol` | `safeSubtract`, `available(balance, liabilities)` | Solvency arithmetic that floors at zero instead of underflowing |
| `AuctionMath` | `AuctionMath.sol` | `nextMinimumBid(highestBid, increment)`, `shouldExtend(...)` | Bid-floor and anti-sniping decisions |
| `AuctionPhaseLib` | `AuctionPhaseLib.sol` | `Clock` struct + `currentPhase`, `requirePhase`, `timeRemaining`, `tryExtendReveal` | BlindAuction time machine; emits `RevealDeadlineExtended` |
| `AutomationScanLib` | `AutomationScanLib.sol` | `MAX_SCAN = 500`, `MAX_ITEMS = 100`, `window(total, cycle, maxScan)`, `capacity(maxItems, startId, endId)` | Bounded, rotating discovery windows shared by every automation view |
| `FeeMath` | `FeeMath.sol` | `BPS = 10_000`, `fee(amount, bps)`, `split(amount, protocolBps)` | Fee arithmetic with an overflow guard for `bps > BPS` |
| `ListingMath` | `ListingMath.sol` | `activeAt(nowTs, expiresAt)`, `isStale(nowTs, expiresAt)` | Listing/offer expiry predicates |
| `OrderHashLib` | `OrderHashLib.sol` | `LISTING_TYPEHASH`, `hashStruct(...)` | EIP-712 struct hashing for signed orders |
| `PhaseLogic` | `PhaseLogic.sol` | `afterEnd(nowTs, deadline)` | Shared "past the deadline" predicate |
| `RaffleMath` | `RaffleMath.sol` | `pickWinningTicket(randomWord, totalTickets)`, `findEntrant(entrants, ticketIndex)` | Uniform ticket selection and binary search over entrant spans |
| `RewardMath` | `RewardMath.sol` | `SCALE = 1e18`, `userAccrued(...)`, `rewardPerToken(...)` | Staking accumulator arithmetic |

`AutomationScanLib.window` is the single source of truth for what "bounded discovery" means:

```text
total == 0 or maxScan == 0        -> (1, 1)            // empty window
maxScan > MAX_SCAN                -> maxScan = 500
span     = min(total, maxScan)
windows  = ceil(total / span)
startId  = 1 + (cycle % windows) * span
endId    = min(startId + span, total + 1)
```

`capacity` then clamps the returned item count to `min(maxItems, endId - startId)` with
`maxItems <= MAX_ITEMS = 100`. Every domain discovery view uses this pair, so a caller can bound both
*iterations* and *results* independently.

---

## Deployer libraries

| Library | File | Deploys |
| --- | --- | --- |
| `CoreDeployer` | `CoreDeployer.sol` | `Treasury`, `PaymentManager`, ERC-1967 proxy |
| `NFTDeployer` | `NFTDeployer.sol` | `CustomNFT` (plain and CREATE2) |
| `AuctionDeployer` | `AuctionDeployer.sol` | `OpenAuction`, `DutchAuction` |
| `BlindAuctionDeployer` | `BlindAuctionDeployer.sol` | `BlindAuction` (parameter struct) |
| `StakingDeployer` | `StakingDeployer.sol` | `Staking` |
| `RaffleDeployer` | `RaffleDeployer.sol` | `Raffle` (parameter struct) |

All six are `internal`-only and are called via `delegatecall`, so they run in the Factory's context. They
carry no state and no access control of their own — all authority checks live in the Factory.

# Security Model

This document describes what the protocol trusts, what it assumes, what it enforces at runtime, and
where the boundaries of those enforcement mechanisms are. It is written to be useful to an external
reviewer and to an operator, not to reassure either.

> **This is not an audit.** The repository is a production-oriented engineering reference implementation.
> It has not been independently audited. Passing every test in this repository is not a substitute for an
> external security review, live dependency verification, or operational review. See
> [`SECURITY.md`](../SECURITY.md) for the reporting policy.

---

## 1. Trust boundaries

| # | Boundary | Trusted for | Not trusted for | Enforcement |
| --- | --- | --- | --- | --- |
| 1 | OpenZeppelin Contracts `v5.4.0` and Contracts Upgradeable `v5.4.0` | `Ownable2Step`, `AccessControl`, `TimelockController`, `Pausable`, `ReentrancyGuard`, `ERC1967Proxy`, `UUPSUpgradeable`, `ECDSA`, `Math.mulDiv`, `Strings` | — | Both vendored trees are pinned to the same release |
| 2 | Chainlink VRF V2.5 coordinator | Delivering `rawFulfillRandomWords` with the recorded `requestId` | Any other caller or request id | `requestIdToCoordinator[requestId]` must equal `msg.sender`; raffle phase and `vrfRequestId` must match; `randomWords.length == 1` |
| 3 | Chainlink CRE forwarder | Authenticating the report envelope and the workflow metadata | The report *contents* | Forwarder address allowlist, workflow id + author configured on-chain, 224-byte payload shape, exhaustive action allowlist, registry lookups, replay map, schedule skew bound |
| 4 | External ERC-721 contracts | `ownerOf`, `transferFrom`, `safeTransferFrom` behave per ERC-721 | Non-standard or malicious implementations | `nft.code.length != 0` at every entry point; ownership re-verified immediately before settlement; `safeTransferFrom` used wherever a receiver hook matters |
| 5 | Treasury payers | Acting within `availableBalance()` and their daily allowance | — | `pay()` cannot exceed unencumbered funds; the rescue path is bounded the same way |
| 6 | Users and contract receivers | Nothing | Reverting receivers, reentrancy, gas griefing | Pull-based refunds and withdrawals; `nonReentrant` on every value-moving function; `receive()` reverts in auction, raffle, and payment contracts |
| 7 | Deployer environment | Correct configuration at broadcast time | — | `forge script script/Preflight.s.sol --rpc-url "$RPC_URL"` with an explicit `EXPECTED_CHAIN_ID`; second-operator review before broadcast |
| 8 | Governance / Timelock | Executing scheduled operations after the delay | — | Delay is a constructor parameter; bootstrap admin should be `address(0)` |

---

## 2. Adversarial capabilities considered

The design assumes an attacker can do all of the following. Each row states where the defence lives.

| Capability | Defence |
| --- | --- |
| Call any public function with arbitrary parameters | Input validation at every entry point; zero-address, zero-value, bounds, and phase checks |
| Re-enter through an ERC-721 receiver hook | `nonReentrant` on every function that moves value; state is written before external calls in settlement paths |
| Front-run a commitment | `commitmentUsed` makes a commitment hash single-use, so copying another bidder's commitment is rejected |
| Copy and replay a signed order | Per-seller monotonic nonce; `invalidateNonce()` as a panic button |
| Replay an automation report on another chain or instance | `chainSelector` is fixed at construction; `instance` must be an active registered record of the expected kind; replay key includes the instance |
| Submit a stale or future-dated automation report | `scheduledAt != 0` and `scheduledAt <= block.timestamp + 10 minutes` |
| Race a refund batch | Reports must carry the current on-chain `refundCursor`; a stale cursor reverts |
| Force ETH into a contract | Every escrow contract asserts `balance >= liabilities` rather than `balance == liabilities`, so forced ETH creates surplus, not inconsistency |
| Grief a sale with a reverting receiver | No push-payment path to a user-controlled address in the marketplace sale flow; users pull from the Treasury |
| Push a raffle into an unrecoverable state by withholding the callback | The coordinator is trusted to deliver; if it does not, the stuck-raffle path opens after 24 hours |
| Drain unencumbered funds through the rescue path | `emergencyRescue` is bounded by `availableBalance()`, which excludes all user liabilities |
| Claim more than owed from the Treasury or PaymentManager | Both ledgers zero the balance **before** transferring; claimable balances are only ever incremented by authorised credits |
| Deploy a lookalike instance and register it | Only the Factory is a registrar; the Factory registers instances it created itself |

---

## 3. Accounting invariants

Each domain enforces its own solvency assertion at runtime. These are not test-only helpers; a violation
reverts the state transition rather than producing an insolvent contract.

| Domain | Invariant | Enforcement point |
| --- | --- | --- |
| Marketplace | `balance >= totalOfferEscrow` | `_assertOfferEscrow()` after `makeOffer`, `acceptOffer`, `cancelOffer`, `expireOffer`, `rejectOffer` |
| OpenAuction | `balance >= totalActiveBidLiability + totalRefundLiability` | `_assertEscrowInvariant()` after `finalizeAuction`, `buyout`, `cancelAuction`, `withdrawRefund` |
| BlindAuction | `balance >= totalPendingReturns + totalUnrevealedDeposits (+ highestBid)` | `_assertEscrowInvariant()` after finalisation, cancellation, and each withdrawal |
| Raffle | `balance >= totalActiveRaffleFunds + totalRaffleRefundLiability` | `_assertInvariant()` after fulfilment, refund batching, cancellation, and claims |
| Staking | `balance >= totalStaked + totalRewardLiability + rewardReserve` | `rewardInventory()` derived; enforced by `InsufficientRewardInventory` on payout |
| Treasury | `totalLiabilities <= balance`, `availableBalance() >= 0` | `AccountingMath.available`, enforced on `pay` and `emergencyRescue` |
| PaymentManager | `totalClaimable <= balance` | Constructed by `credit` plus the direct-payment rejection in `receive()` |
| Registry | Every record points at an address with code | `registerInstance` rejects empty instances |

A design property worth stating explicitly: **`address(this).balance` is never assumed to be authoritative.**
Every invariant is one-sided (`balance >= liabilities`), so an attacker who can force ETH into a contract
increases surplus but can never break an assertion.

---

## 4. Access control matrix

| Action | Marketplace | CustomNFT | Auctions | Staking | Raffle | Treasury | PaymentManager | Factory | Registry | Receiver |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Configure fees | `ADMIN_ROLE` | — | constructor | `onlyOwner` | `onlyOwner` | — | — | — | — | — |
| Pause | `OPERATOR_ROLE` | `OPERATOR_ROLE` | `onlyOwner` | `onlyOwner` | `onlyOwner` | — | — | — | — | `onlyOwner` |
| Set dependencies | `ADMIN_ROLE` | — | — | — | — | — | — | — | — | — |
| Grant roles | `DEFAULT_ADMIN_ROLE` | `DEFAULT_ADMIN_ROLE` | `onlyOwner` | `onlyOwner` | `onlyOwner` | `onlyOwner` | `onlyOwner` | `onlyOwner` | `onlyOwner` | `onlyOwner` |
| Move funds | — | — | settlement | — | — | `authorizedPayer` | `authorizedCreditor` | — | — | — |
| Upgrade | `DEFAULT_ADMIN_ROLE` | — | — | — | — | — | — | — | — | — |
| Finalise controllers | — | — | — | — | — | `onlyOwner` | `onlyOwner` | `onlyOwner` | — | — |
| Configure automation identity | — | — | — | — | — | — | — | — | — | `onlyOwner` |

Two roles are deliberately narrow: `OPERATOR_ROLE` on the Marketplace and CustomNFT can pause and nothing
else, and `METADATA_ROLE` on CustomNFT cannot move tokens.

---

## 5. Reentrancy posture

The rule applied throughout: **`nonReentrant` guards every function that makes an external call to an
untrusted contract and then continues to use state.** The complete list, extracted from the source:

| Contract | Functions carrying `nonReentrant` |
| --- | --- |
| Marketplace | `buy`, `cancelOffer`, `expireOffer`, `acceptOffer`, `rejectOffer`, `executeSignedListing` |
| OpenAuction | `createAuction`, `placeBid`, `buyout`, `cancelAuction`, `finalizeAuction`, `withdrawRefund` |
| BlindAuction | `reveal`, `finalizeAuction`, `withdraw`, `withdrawUnrevealed`, `withdrawIfCancelled` |
| DutchAuction | `createAuction`, `buy`, `cancelAuction`, `expireAuction` |
| Raffle | `createRaffle`, `buyTickets`, `requestRandomWinner`, `retryRandomWinnerRequest`, `cancelStuckRaffle`, `processRaffleRefunds`, `claimRaffleRefund`, `rawFulfillRandomWords`, `finalizeFailedRaffle`, `cancelRaffle` |
| Staking | `stake`, `unstake`, `claimReward`, `compoundReward`, `emergencyUnstake` |
| CustomNFT | both `safeTransferFrom` overloads |
| Treasury | `pay`, `withdrawClaimable`, `emergencyRescue` |
| PaymentManager | `withdraw` |
| ProtocolFactory | every `create*` entry point |

Functions that make **no** state-advancing external call are deliberately left unguarded, because the
guard would add gas with no benefit. Two kinds exist:

- **Static-only reads.** For example `BlindAuction.placeBid` and `Marketplace.makeOffer` call `ownerOf`
  / `code.length`, which compile to `STATICCALL` and cannot modify state.
- **Calls to already-trusted, protocol-owned contracts.** For example `Treasury.pay`'s recipient is
  caller-supplied and protected, while `Staking.fundRewardsFromTreasury` calls the configured Treasury —
  and is `onlyOwner`.

Where a function calls an untrusted address and the call could fail, the design prefers
**check → effect → interaction** ordering plus the escrow assertion, rather than relying on the guard alone.
Example: `OpenAuction.finalizeAuction` decrements `totalActiveBidLiability` and updates the phase before
transferring the NFT, then asserts the invariant.

The `reentrancy-eth` findings reported by `forge lint` correspond exactly to the guarded functions listed
above, which is why the lint baseline treats them as reviewed rather than as open issues. See
[LINTING.md](LINTING.md) for the full finding inventory and its adjudication status.

---

## 6. Economic assumptions

| Assumption | Consequence if violated |
| --- | --- |
| `block.timestamp` is a usable clock | Auctions, offers, raffles, mint windows, staking schedules, and the daily Treasury window all read it. Validators can nudge it by seconds. Every window in this protocol is minutes-to-days wide, except the 5-minute reveal and anti-sniping windows. |
| Chainlink VRF output is uniformly distributed and unpredictable | Fairness of raffle winner selection |
| Chainlink CRE delivers reports with faithful metadata | Authenticity of automated state transitions — but the *effect* is bounded: every automated action is one a permissionless caller could also perform |
| An ERC-721 transfer to a contract either succeeds or reverts | Escrow release correctness; `safeTransferFrom` is used where a hook runs |
| The Treasury owner is the intended governance address | Spending authority and payer authorisation |
| Gas costs let a refund batch of 12 complete inside `gasLimit` | `refundBatchSize = 12` is backed by a measured gas test; raising it requires re-measuring |

---

## 7. Known design limitations

These are real, documented, and unresolved. Each one is a decision that should be made explicitly before
a production deployment.

### 7.1 Blind auction creation after controller finalisation

`ProtocolFactory.createBlindAuctionInstance` grants the new contract Treasury payer rights:

```solidity
ITreasury(treasury_).setAuthorizedPayer(instance, true);
```

`Treasury.setAuthorizedPayer` accepts either the owner or the `factoryController`. After
`finalizeProtocolSuiteControllers` the controller is `address(0)`, so this call reverts.

**Consequence.** On a finalised protocol, `createBlindAuctionInstance` cannot be used against the
governance-controlled Treasury. Each new blind auction would need a Timelock operation calling
`Treasury.setAuthorizedPayer` directly.

**Decision required before mainnet.** Either accept the operational coupling, exclude BlindAuction from
the finalised-suite flow, or redesign the payer-authorisation path for per-NFT instances.

### 7.2 Offer refunds are blocked while the Marketplace is paused

`cancelOffer` and `expireOffer` are both `whenNotPaused`. While the Marketplace is paused, a buyer with an
active offer cannot reclaim their escrowed funds, and neither can anyone else expire the offer.

**Consequence.** Pausing the Marketplace freezes buyer funds in escrow until it is unpaused.

**Decision required.** Either remove `whenNotPaused` from the refund paths, or document pausing as a
deliberate escrow freeze with an operational commitment to unpause promptly.

### 7.3 Pausing a collection freezes settlement elsewhere

`CustomNFT` applies `whenNotPaused` to transfers, approvals, and burning. A paused collection cannot
settle an auction, raffle, or listing that escrows one of its tokens.

**Decision required.** Treat collection pause as a last-resort lever, or scope pausing to minting only.

### 7.4 The stuck-raffle path depends on the creator

If a VRF callback never arrives, only the raffle creator (after 24 hours) can call `cancelStuckRaffle`.
The Raffle owner can cancel only raffles with zero tickets sold. A creator who is unavailable leaves that
raffle's funds escrowed indefinitely from the protocol's point of view.

**Decision required.** Consider allowing the Raffle owner to cancel a stuck raffle after the delay, which
is a privilege trade-off between liveness and creator autonomy.

### 7.5 `pendingReturns` and `refunds` mappings are never emptied entry-by-entry

Refund withdrawals zero the individual entry they pay out, so there is no unbounded-growth issue in the
hot path. However, the mappings retain a zeroed slot per address forever. This is gas-only, not a
correctness or solvency issue.

---

## 8. Operational security requirements

| Requirement | Reason |
| --- | --- |
| Never commit `.env`, private keys, RPC URLs, or API keys | `.gitignore` covers `.env` and `.env.*` except `.env.example`; the deployment runbook repeats the rule |
| Never broadcast without `forge script script/Preflight.s.sol --rpc-url "$RPC_URL"` | The preflight script is the only automated check of chain id, deployer, governance target, fee recipient, and VRF configuration |
| Never accept ownership for a Timelock from an EOA path | `AcceptEOAProtocolOwnershipScript` is only valid for an EOA final owner; a `Ownable2Step` contract owned by a Timelock must accept through a scheduled Timelock operation |
| Verify the target-chain VRF configuration independently | The repository pins Chainlink `contracts-v1.5.0`, but coordinator addresses and gas lanes are deployment inputs that must be checked against current official documentation |
| Verify the Keystone forwarder address before receiver deployment | The receiver's trust in the forwarder is the whole basis of report authenticity |
| Keep `refundBatchSize` and `gasLimit` in sync with the gas test | `test/automation/ProtocolAutomationGas.t.sol` is the source of truth for both constants |
| Treat a pausing decision as an economic decision | See §7.2 and §7.3 |

---

## 9. What is *not* covered

Stated plainly, so nothing here is mistaken for a guarantee:

- **No third-party audit.** Nothing in this repository has been reviewed by an independent security firm.
- **No formal verification of the contracts.** The `verification/symbolic/` harnesses cover arithmetic
  properties in `FeeMath`, `AuctionMath`, and `RewardMath` only; they are not a whole-protocol proof.
  Mutation testing (`verification/mutation/`) measures test strength, not correctness.
- **No economic modelling.** Fee levels, incentive compatibility of the anti-sniping windows, and griefing
  costs are not analysed beyond the property tests in the suite.
- **No adversarial simulation of the CRE workflow itself.** The workflow is verified by TypeScript unit
  tests and an on-chain integration suite; the network-level security of a CRE deployment is Chainlink's
  responsibility.
- **No analysis of fork-specific behaviour.** EVM equivalence, gas-schedule differences, and precompile
  availability are assumed, not verified, except where the fork suite touches the raffle.
- **No coverage of deployment-script correctness beyond tests.** The scripts are exercised by
  `test/automation/AutomationScripts.t.sol` and the deployment suites, but a script that mutates live state
  correctly in a test can still be misconfigured in production.

---

## 10. Reporting a vulnerability

Follow [`SECURITY.md`](../SECURITY.md): do not disclose an unpatched vulnerability publicly; provide a
minimal reproduction, the affected contract, the impact, and a suggested mitigation through the private
channel maintained by the repository owner.

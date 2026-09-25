# Architecture

Ali Voryn Protocol is a modular Solidity/EVM protocol suite. It is not a single-purpose contract with
features bolted on; it is a set of independently deployable domains that share three things: a
**registry** for discovery, a **treasury/payment layer** for accounting, and a **factory** for deployment.

This document explains the boundaries between those pieces and the rules that keep them honest.

---

## 1. Design rules

These are the constraints the codebase is built to satisfy. They are the reference for deciding whether a
change is architectural or incidental.

| # | Rule | Where it is enforced |
| --- | --- | --- |
| 1 | Financial components track assets, claims, and liabilities explicitly | `Treasury.totalLiabilities`, `PaymentManager.totalClaimable`, `OpenAuction.totalActiveBidLiability` + `totalRefundLiability`, `BlindAuction.totalPendingReturns` + `totalUnrevealedDeposits`, `Marketplace.totalOfferEscrow`, `Raffle.totalActiveRaffleFunds` + `totalRaffleRefundLiability`, `Staking.totalStaked` + `totalRewardLiability` |
| 2 | External callbacks are authenticated before any state transition | `Raffle.rawFulfillRandomWords` validates coordinator and request binding first; `ProtocolAutomationReceiver._processReport` validates forwarder, workflow identity, registry record, and replay key before dispatch |
| 3 | Privileged operations are explicit in ownership, roles, and governance | `Ownable2Step` on auctions, staking, treasury, payment manager, factory, registry, raffle, receiver; `AccessControl` on `Marketplace` and `CustomNFT` |
| 4 | Upgradeability is used only where operationally justified | Only `Marketplace` is upgradeable (UUPS). Auctions, staking, raffle, treasury, payment manager, NFT, factory, and registry are immutable |
| 5 | Domain behaviour is kept close to its tests | `test/<domain>/<Contract>.<Methodology>.t.sol` — see [test-matrix.md](test-matrix.md) |
| 6 | Deployment configuration is explicit and reproducible | Pinned toolchain and dependencies, explicit env vars, `forge script script/Preflight.s.sol --rpc-url "$RPC_URL"` before any broadcast |
| 7 | Core contracts never depend on the automation layer | `src/core/**` contains no import of `src/automation/**`. Automation reads through public views and writes through public lifecycle functions |
| 8 | Automation is fail-closed | `ProtocolAutomationReceiver` is constructed paused and refuses to unpause without a workflow id **and** author |

---

## 2. System map

```text
        ProtocolTimelock (TimelockController)
                    |
        owner / admin / proposer
                    |
    +---------------+----------------+
    |               |                |
    v               v                v
ProtocolFactory  Treasury      PaymentManager
  Ownable2Step   Ownable2Step    Ownable2Step
    |               ^                ^
    | creates       | credit / pay   | credit
    | registers     |                |
    v               |                |
ProtocolRegistry ---+----------------+
  Ownable2Step      |
    |               |
    | discovery     |  revenue & escrow flow
    | views         |
    v               |
Automation read     +--> Marketplace (UUPS proxy)
boundary            +--> OpenAuction / BlindAuction / DutchAuction
                    +--> Staking
                    +--> Raffle  <-- Chainlink VRF V2.5
                    +--> CustomNFT


ProtocolAutomationReceiver (paused by default)
        ^
        | KeystoneForwarder
        |
Chainlink CRE workflow (cron trigger)
```

Three structural facts follow from this map:

1. **The Factory is a deployment and registration service, not a controller.** After
   `finalizeProtocolSuiteControllers`, the Factory's authority over the Treasury and PaymentManager is
   revoked permanently.
2. **Treasury is a liability ledger, not a vault controlled by the domains.** Domains call
   `credit{value: ...}` to record who is owed what; recipients withdraw. Two exceptions are deliberate:
   the Marketplace routes offer refunds through `PaymentManager`, and no domain can spend from the
   Treasury except through the explicitly authorised payer path.
3. **Automation is outside the trust boundary of the domains.** The receiver can only call functions any
   third party could call; its value is in *scheduling* and *report authenticity*, not in privilege.

---

## 3. Module map

| Layer | Directory | Contents | Responsibility |
| --- | --- | --- | --- |
| Domains | `src/core/` | `Marketplace`, `OpenAuction`, `BlindAuction`, `DutchAuction`, `Staking`, `Raffle`, `CustomNFT` | Business behaviour and domain accounting |
| Accounting | `src/core/` | `Treasury`, `PaymentManager` | Custody of recorded liabilities; pull-based withdrawal |
| Deployment | `src/factory/` | `ProtocolFactory` | CREATE2 deployment, wiring, registry registration |
| Deployment internals | `src/factory/deployers/` | 6 external libraries | Creation code, kept out of the Factory runtime |
| Discovery | `src/registries/` | `ProtocolRegistry` | Instance records, indexing, bounded automation enumeration |
| Control | `src/governance/` | `ProtocolTimelock` | TimelockController-based control plane |
| Automation | `src/automation/` | `ProtocolAutomationReceiver`, `ProtocolAutomationSimulationReceiver` | Fail-closed on-chain report boundary |
| Automation base | `src/automation/chainlink/` | `ReceiverTemplate`, `IReceiver` | Vendored Chainlink template |
| Interfaces | `src/interfaces/` | 11 interfaces | External API surface and shared types |
| Math and policy | `src/libraries/` | 10 libraries | Pure arithmetic, phase logic, hashing, scanning |

Total: **43 Solidity files, 4,476 lines** under `src/`.

---

## 4. Why the deployer libraries exist

`ProtocolFactory` deploys every protocol contract. If it embedded their creation code it would exceed the
limits that matter:

- **EIP-170** — deployed runtime code must stay under 24,576 bytes.
- **EIP-3860** — initcode (including constructor arguments and library-linking metadata) is limited to
  49,152 bytes.

Contract creation therefore lives in six external libraries under `src/factory/deployers/`:
`CoreDeployer`, `NFTDeployer`, `AuctionDeployer`, `BlindAuctionDeployer`, `StakingDeployer`,
`RaffleDeployer`. The Factory calls them with `delegatecall`.

Because a `delegatecall`'d library executes **in the Factory's context**, the observable semantics are
unchanged: `msg.sender`, the CREATE2 deployer address, and the resulting contract addresses are exactly
what they would be if the creation code were inline. Only the bytecode storage moved.

Consequences that matter operationally:

- A Factory deployment produces **seven contracts to source-verify**: the six libraries plus the Factory.
  The Registry and the Marketplace implementation are created inside the Factory constructor, so they are
  also part of the same deployment transaction.
- Foundry links the libraries automatically in tests and in `forge script`, so no manual linking step is
  required — but a verifier must not forget the libraries.

---

## 5. Authority over Treasury payer rights

A **Treasury payer** is an address allowed to move *unencumbered* Treasury funds via `pay`. This is the
single most dangerous permission in the protocol, so its grant path is narrowed deliberately.

```text
Treasury.setAuthorizedPayer(payer, true)
        |
        +-- caller == Treasury.owner()          -> allowed
        |
        +-- caller == Treasury.factoryController -> allowed
                    |
                    +-- Factory grants payer rights to contracts it creates
                        ONLY IF the caller already controls the Treasury:
                        createStaking    requires caller == owner or pendingOwner
                        createMarketplace requires caller == owner or pendingOwner
```

Instance types that cannot spend Treasury funds — OpenAuction, DutchAuction, BlindAuction, and Raffle —
remain creatable by any caller, because granting them payer rights carries no spending risk for the
Treasury beyond what their own settlement logic already credits.

After `finalizeProtocolSuiteControllers`, the Factory loses payer-granting rights entirely. From that
point only the Treasury owner (expected: the Timelock) can authorise new payers. This is intentional and
has one documented consequence; see [security.md](security.md#known-design-limitations).

---

## 6. Authority model

| Contract | Ownership / role model | Expected production holder |
| --- | --- | --- |
| `ProtocolTimelock` | `TimelockController` roles: proposer, executor, admin | Self-administered after bootstrap removal |
| `ProtocolFactory` | `Ownable2Step` | Timelock |
| `ProtocolRegistry` | `Ownable2Step` + registrar allowlist | Timelock; Factory remains a registrar |
| `Treasury` | `Ownable2Step` + `authorizedPayer` map + `factoryController` | Timelock; controller finalised to `address(0)` |
| `PaymentManager` | `Ownable2Step` + `authorizedCreditor` map + `factoryController` | Timelock; controller finalised to `address(0)` |
| `Marketplace` | `AccessControl`: `DEFAULT_ADMIN_ROLE`, `ADMIN_ROLE`, `OPERATOR_ROLE` | Admin = Timelock; operator assigned deliberately |
| `CustomNFT` | `AccessControl`: `DEFAULT_ADMIN_ROLE`, `MINTER_ROLE`, `OPERATOR_ROLE`, `METADATA_ROLE` | Per-collection admin |
| `OpenAuction`, `DutchAuction` | `Ownable2Step` | Timelock (or per-deployment owner) |
| `BlindAuction` | `Ownable2Step` + immutable `beneficiary` | Per-auction; one contract per NFT |
| `Staking` | `Ownable2Step` | Timelock |
| `Raffle` | `Ownable2Step` | Timelock |
| `ProtocolAutomationReceiver` | `Ownable2Step` + `Pausable` | Timelock or a dedicated automation admin |

Every ownership handoff in this repository uses two-step acceptance (`transferOwnership` →
`acceptOwnership`). A Timelock-owned contract therefore cannot accept ownership in the same transaction
that transfers it; the acceptance must be scheduled through the Timelock. Two scripts exist for exactly
this: `ScheduleGovernanceOwnershipAcceptance.s.sol` and `ExecuteGovernanceOwnershipAcceptance.s.sol`.

---

## 7. Data flow: a marketplace sale

```text
buyer.buy(listingId) {value: price}
   |
   +-- require active listing, seller still owns the NFT, value == price
   |
   +-- feeBps = customFeeEnabled[seller] ? customFeeBps[seller]
   |                                    : max(protocolFeeBps, minimumFeeBps)
   |
   +-- FeeMath.split(price, feeBps) -> (fee, sellerAmount)
   |
   +-- Treasury.credit{value: fee}(feeRecipientForProtocol(), "MARKETPLACE_FEE")
   |        -> totalLiabilities += fee
   |
   +-- Treasury.credit{value: sellerAmount}(seller, "MARKETPLACE_PROCEEDS")
   |        -> claimableBalance[seller] += sellerAmount
   |
   +-- CustomNFT.safeTransferFrom(seller, buyer, tokenId)
   |
   +-- emit ListingSold


seller.withdrawClaimable()                 (Treasury)
   +-- claimableBalance[seller] = 0
   +-- totalLiabilities -= amount
   +-- transfer to seller
```

Two properties this shape guarantees:

- **No direct ETH movement between users.** Every participant receives funds by pulling from the Treasury
  or the PaymentManager. There is no push-payment path to a user-controlled address in the sale flow, so a
  reverting receiver cannot block a sale.
- **The sale is atomic with respect to accounting.** Either the NFT moves and both credits are recorded, or
  the whole transaction reverts.

---

## 8. Data flow: an auction finalisation

```text
OpenAuction.finalizeAuction(id)
   |
   +-- if phase == Active and now >= endAt -> phase = Ended
   |
   +-- successful = highestBidder != 0 && highestBid >= reservePrice
   |
   +-- if successful:
   |      totalActiveBidLiability -= highestBid
   |      NFT: escrow -> winner
   |      FeeMath.split(highestBid, protocolFeeBps)
   |      Treasury.credit fee       -> fee recipient
   |      Treasury.credit remainder -> seller
   |
   +-- else:
   |      highestBidder credited to refunds[bidder]  (pull-based)
   |      NFT: escrow -> seller
   |
   +-- _assertEscrowInvariant():
          address(this).balance >= totalActiveBidLiability + totalRefundLiability
```

The escrow assertion is a **runtime invariant guard**, not merely a test helper. If accounting and balance
ever diverge, the state transition reverts instead of silently producing an insolvent contract.

---

## 9. Data flow: automation

```text
Chainlink CRE workflow (cron, every minute by default)
   |
   +-- ProtocolAutomationReceiver.paused()                  1 read
   |
   +-- ProtocolRegistry.automationInstancesWithCycle(kind, offset, limit)
   |        one call per kind (5 kinds)                     5 reads
   |
   +-- domain discovery on the selected instance
   |        automationDueIds / automationDueOfferIds /
   |        automationCandidates(cycle, maxScan, maxItems)  1 read
   |
   +-- signed report:  action | instance | id | value | cursor
   |                   scheduledAt | chainSelector
   |
   v
KeystoneForwarder
   v
ProtocolAutomationReceiver._processReport(report)
   +-- paused check
   +-- msg.sender == getForwarderAddress()
   +-- workflow identity configured
   +-- report.length == 224, abi.decode
   +-- _validate(): registry active, expected kind per action, schedule skew,
   |                refund batch bounds, refund cursor match
   +-- replayKey not seen before
   +-- dispatch to the domain function (explicit allowlist, no arbitrary call)
   v
Domain function executes the same state transition a human could trigger
```

The default configuration performs **11 EVM reads** before any write, against a documented budget of 15
reads per execution. See [AUTOMATION.md](AUTOMATION.md) for the gas and rotation model.

---

## 10. Trust boundaries

| Boundary | What is trusted | What is not | Mitigation |
| --- | --- | --- | --- |
| OpenZeppelin primitives | `Ownable2Step`, `AccessControl`, `TimelockController`, `Pausable`, `ReentrancyGuard`, UUPS proxy | — | Pinned to `v5.4.0`; upgradeable variant pinned identically |
| Chainlink VRF | Coordinator delivers the callback with the recorded `requestId` | Any other caller | `requestIdToCoordinator[requestId]` check before any state change; unknown request ids are rejected |
| Chainlink CRE | KeystoneForwarder authenticates the report envelope; workflow identity is configured on-chain | Arbitrary reports | Forwarder allowlist, workflow id + author check, registry kind check, replay map, schedule skew window |
| External NFT contracts | That `ownerOf` / `transferFrom` / `safeTransferFrom` behave per ERC-721 | Non-standard implementations | `nft.code.length != 0` checks at every entry point; ownership re-verified before settlement |
| Users and receivers | Nothing | Reverting receivers, reentrant callbacks | Pull-based refunds, `nonReentrant` on every value-moving function, `Receive`/`fallback` that rejects direct payments in auction, raffle, and payment contracts |
| Deployer | Correct environment configuration at broadcast time | — | `forge script script/Preflight.s.sol --rpc-url "$RPC_URL"` gate, explicit `EXPECTED_CHAIN_ID`, second-operator review |
| Governance | Timelock delay and proposer set | — | Delay is a constructor argument; bootstrap admin should be `address(0)` |

---

## 11. Extension points

Adding a new domain is a defined procedure rather than an open-ended change:

1. Add the interface to `src/interfaces/`.
2. Add the implementation to `src/core/`.
3. If it needs Treasury or PaymentManager rights, add a `create*Instance` path to `ProtocolFactory` and
   apply the correct authority rule (see §5).
4. Add a `KIND_*` constant to `ProtocolFactory`, and — if automation should reach it — to
   `ProtocolAutomationReceiver` with an explicit `Action` enum member and a validation branch.
5. Add the domain directory under `test/` with the methodology suffixes that add real coverage (see
   [test-strategy.md](test-strategy.md)).
6. Add the deployment and verification wiring to the relevant scripts under `script/`.
7. Sync this document set.

Step 4 is the only one with a security-critical failure mode: adding an action without adding it to
`_validate` would allow an unintended target. The receiver's `_validate` is exhaustive over the `Action`
enum, and any new member must be handled in both `_validate` and `_processReport`.

---

## 12. Where to go next

- Behaviour inventory: [features.md](features.md)
- Contract reference: [contracts.md](contracts.md)
- Threat model and limitations: [security.md](security.md)
- Verification layers: [test-strategy.md](test-strategy.md), [test-matrix.md](test-matrix.md)
- Deployment: [deployment.md](deployment.md), [mainnet.md](mainnet.md)

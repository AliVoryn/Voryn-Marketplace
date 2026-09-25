# Glossary

Precise definitions of the terms used throughout this documentation. Where a term maps to a specific
identifier, state variable, or role in the code, the identifier is given.

---

## Actors and authority

**Admin** — holder of `DEFAULT_ADMIN_ROLE` (Marketplace, CustomNFT) or the owner of an `Ownable2Step`
contract. Configures the protocol; cannot move user funds in any domain.

**Beneficiary** — the `address payable` that receives the NFT if a `BlindAuction` fails to meet its
reserve, and the address that receives proceeds on success. Immutable for the life of the auction
contract.

**Creator** — the account that created a protocol instance. In `Raffle` and `CustomNFT` it is the owner of
the escrowed NFT; in the Factory it is the account recorded in `instancesByCreator`.

**Deployer** — the account that signs the deployment transactions. Holds no protocol authority after
handover.

**Governance** — the `ProtocolTimelock` (`TimelockController`). Becomes the control plane only where
contracts are actually owned or administered by it.

**Operator** — holder of `OPERATOR_ROLE`. Can pause and unpause; cannot configure or move funds.

**Owner** — the address returned by `owner()`. On critical contracts the target state is the Timelock.

**Payer** — an address authorised on the `Treasury` to `credit` and `pay`. Granted by the Treasury owner or
by the Factory controller (while it still exists).

**Registrar** — an address authorised on the `ProtocolRegistry` to call `registerInstance`. The Factory is
one; it registers instances it created itself.

**Creditor** — an address authorised on the `PaymentManager` to call `credit`.

**Pending owner** — the address that has been offered ownership by an `Ownable2Step` transfer but has not
yet called `acceptOwnership()`. Until acceptance, the previous owner retains authority.

**Timelock** — see *Governance*.

## Accounting

**Claimable balance** — an amount recorded as owed to a specific account in `Treasury` or
`PaymentManager`. Withdrawable by that account only, via a pull call.

**Credit** — recording a liability to an account without transferring value to it. `Treasury.credit` and
`PaymentManager.credit` both take the value and attribute it.

**Escrow** — value held by a contract on behalf of a future settlement. Tracked explicitly:
`Marketplace.totalOfferEscrow`, `OpenAuction.totalActiveBidLiability`, `BlindAuction.totalUnrevealedDeposits`,
`Raffle.totalActiveRaffleFunds`.

**Liability** — the total amount the protocol owes. `Treasury.totalLiabilities`,
`PaymentManager.totalClaimable`, `Staking.totalRewardLiability`, `OpenAuction.totalRefundLiability`,
`Raffle.totalRaffleRefundLiability`.

**Unencumbered balance** — `Treasury.availableBalance() = max(0, balance - totalLiabilities)`. The only
funds a payer can spend, and the ceiling for `emergencyRescue`.

**Pull payment** — a pattern where the protocol records what it owes and the recipient withdraws it,
instead of pushing funds during the state transition. Every user-facing payout in this protocol is a pull
payment, which removes the reverting-receiver griefing vector.

**Push payment** — a direct transfer during a state transition. Used in exactly two places, both to an
address the caller controls: the DutchAuction excess refund and the Staking unstake payout.

**Reward inventory** — `Staking.rewardInventory() = balance - (totalStaked + totalRewardLiability +
rewardReserve)`. The free surplus available to fund a new reward program.

**Surplus** — balance in excess of all recorded liabilities. ETH forced into a contract creates surplus,
never an accounting inconsistency, because every invariant is one-sided (`balance >= liabilities`).

## Auctions and markets

**Anti-sniping extension** — a rule that a bid placed inside the final extension window pushes the deadline
back. `OpenAuction`: 5-minute window, 5-minute extension, at most 3 times.

**Bid increment** — `minIncrement`, the minimum amount by which a new bid must exceed the current highest
bid.

**Blinded bid / commitment** — `keccak256(abi.encodePacked(value, fake, secret))`. Published during the
bidding phase; the value is revealed later. Single-use: `commitmentUsed[hash]`.

**Buyout** — an optional immediate-purchase price attached to an `OpenAuction`. Must exceed the reserve and
the standing highest bid.

**Dutch auction** — a declining-price auction. Price interpolates linearly from `startPrice` to `endPrice`
between `startAt` and `endAt`, and is clamped at both boundaries.

**Fake bid** — a commitment whose `fake` flag is true. Revealing it proves the bidder participated without
revealing a real value; the deposit is refunded.

**Listing** — a fixed-price sale entry in the Marketplace. States: `None`, `Active`, `Sold`, `Cancelled`,
`Expired`.

**Offer** — an escrowed bid to buy an unlisted token. States: `None`, `Active`, `Accepted`, `Cancelled`,
`Rejected`, `Expired`.

**Reserve price** — the minimum acceptable price. If the highest bid is below it at finalisation, the
auction fails and the NFT returns to the seller (or the beneficiary, for blind auctions).

**Reveal extension** — `BlindAuction`'s equivalent of anti-sniping: a valid reveal inside the final
5 minutes extends the reveal window by 5 minutes, at most 3 times.

**Signed listing** — an EIP-712 `ListingOrder` signed by a seller, executable by any relayer. Protected by
a per-seller nonce (`orderNonce`) that increments on every execution and can be bumped wholesale with
`invalidateNonce()`.

**Stale** — past its deadline. `ListingMath.isStale` / `activeAt`.

**Unrevealed deposit** — the escrowed value behind a commitment that was never revealed. Reclaimable via
`withdrawUnrevealed()` once the auction reaches `AwaitingFinalization`.

## Verification

**Conformance suite** — `.Conformance.t.sol`. Verifies compatibility with an external standard
(`CustomNFT` against ERC-721; `ProtocolRegistry` against `IRegistry`).

**Deployment suite** — `.Deployment.t.sol`. Verifies wiring and post-deployment assumptions.

**Fork suite** — `.Fork.t.sol`. Verifies behaviour that depends materially on real chain state. Exactly one
exists, for the raffle's VRF integration.

**Fuzz suite** — `.Fuzz.t.sol`. Asserts a property over a sampled input space.

**Invariant suite** — `.Invariant.t.sol`. Asserts a property across arbitrary action sequences driven by
handlers or actors. 14 invariant functions across 11 suites.

**Invariant guard** — a runtime assertion in the contracts that reverts a state transition if accounting
and balance diverge (for example `_assertEscrowInvariant`). Not merely a test helper: it makes an insolvent
state unreachable.

**Methodology suffix** — the trailing element of a test filename (`.Unit.`, `.Fuzz.`, `.Security.`, …) that
makes the verification model explicit without restructuring the directory tree.

**Mutation testing** — introducing controlled source changes and checking whether the suite detects them.
Measures test *strength*, not correctness. Lives in `verification/mutation/`.

**Regression suite** — `.Regression.t.sol`. A permanent reproduction of a previously fixed bug. Created
when a bug is found and never deleted.

**Symbolic verification** — SMT-based analysis of arithmetic properties over all inputs, applied to three
math harnesses under `verification/symbolic/`.

**Security suite** — `.Security.t.sol`. Encodes attacker capabilities rather than happy paths.

**Unit suite** — `.Unit.t.sol`. Deterministic behaviour, boundaries, reverts, events, accounting.

## Automation

**Action** — one of the seven enumerated operations the automation receiver may perform. Indexed 0–6.

**Bounded discovery** — the rule that every discovery view takes `(cycle, maxScan, maxItems)`, caps
iterations at `MAX_SCAN = 500`, and caps results at `MAX_ITEMS = 100`.

**CRE** — Chainlink Runtime Environment. The off-chain TypeScript workflow that discovers eligible work and
submits reports.

**Cycle** — a rotating window index. For registry enumeration it is `offset / count`; for domain scans it
selects which window of the id space to inspect.

**Forwarder** — the Chainlink Keystone forwarder that delivers reports to the receiver. Its address is
configured at receiver construction and is the basis of report authenticity.

**Fail-closed** — a component that refuses to operate until it is correctly configured. The receiver is
constructed paused and cannot be unpaused without both a workflow id and author.

**Partition** — an instance of the workflow with its own `partitionIndex`, used to increase visit
frequency by deploying multiple clones.

**Replay key** — `keccak256(action, instance, id, value, cursor)`. A report whose key has been seen is
rejected.

**Report** — the 224-byte payload submitted by the workflow:
`(uint8 action, address instance, uint256 id, uint256 value, uint256 cursor, uint64 scheduledAt, uint64
chainSelector)`.

**Simulation receiver** — `ProtocolAutomationSimulationReceiver`. A separate receiver that skips workflow
identity validation so `cre workflow simulate` (which uses a MockForwarder without metadata) works without
weakening production validation. Testnets only.

**Workflow identity** — the `(workflowId, workflowAuthor)` pair configured on the receiver. Both must be
non-zero for the receiver to accept reports.

## Protocol and deployment

**Controller finalisation** — `ProtocolFactory.finalizeProtocolSuiteControllers`. Sets
`factoryController` to `address(0)` on both ledgers, permanently revoking the Factory's ability to grant
payer or creditor rights.

**Deployer library** — one of six external libraries holding contract creation code, called by the Factory
via `delegatecall` to keep its runtime under the EIP-170 limit without changing the observable deployment
semantics.

**KIND_*** — a `keccak256` identifier for an instance type (`KIND_MARKETPLACE`, `KIND_RAFFLE`, …).
Registered with every instance and checked by the automation receiver against the action being performed.

**Protocol suite** — the six instances created by `createProtocolSuite`: Treasury, PaymentManager,
Marketplace, OpenAuction, DutchAuction, Staking.

**Registry record** — the struct describing an instance: `instance`, `implementation`, `creator`, `kind`,
`version`, `active`.

## Chainlink VRF

**Callback gas limit** — the gas the VRF coordinator is allowed to spend calling
`rawFulfillRandomWords`. If it is exhausted, the coordinator does not retry and the raffle stalls.

**Coordinator** — the VRF V2.5 coordinator contract. Fixed per raffle; the only address permitted to
fulfil a randomness request.

**Entrant** — a `(buyer, startIndex, ticketCount)` span recorded per ticket purchase. Winner resolution is
a binary search over these spans.

**Request confirmations** — the number of blocks the coordinator waits before fulfilling. Validated to
`[3, 200]`; the repository default is 3.

**Stuck raffle** — a raffle in `AwaitingRandomness` whose callback never arrived. After the 24-hour
`STUCK_RAFFLE_CANCEL_DELAY`, only the creator can cancel it.

**Winning ticket index** — `randomWord % ticketsSold`, mapped to an entrant by `RaffleMath.findEntrant`.

## Verification infrastructure terms

**Gas snapshot** — `forge snapshot` → `forge snapshot`. Records gas usage so a regression is visible as a
diff.

**Profile** — a named configuration block in `foundry.toml`. Three are used: `default`, `ci`, `ci-fast`.

**Preflight** — the read-only pre-broadcast gate (`forge script script/Preflight.s.sol --rpc-url "$RPC_URL"`). Checks chain id, deployer, admin, fee
recipient, raffle fee, and VRF confirmation count, then exits without signing.

**Vendored** — third-party code committed into the repository rather than pulled at build time. Applies to
`src/automation/chainlink/ReceiverTemplate.sol` and the committed `lib/` dependency trees.

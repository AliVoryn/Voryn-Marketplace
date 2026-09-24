# Deployment

How the protocol is deployed, in what order, with which script, and which environment variables.

For a mainnet release with governance handoff, read [mainnet.md](mainnet.md) as well — this document
describes the mechanics, that one describes the release procedure.

---

## 1. Deployment philosophy

Deployment is split by responsibility rather than hidden inside one script. Three consequences follow:

1. **Every step is independently verifiable.** Each script prints the addresses it produced, and
   `VerifyDeployment.s.sol` re-checks the resulting authority graph on-chain.
2. **Nothing is broadcast implicitly.** `make preflight` and `make verify-deployment` are read-only.
   Broadcasting is always an explicit `--broadcast` flag supplied by an operator.
3. **Wiring is asserted, not assumed.** The Factory checks `factoryController` before granting payer
   rights; the Marketplace refuses a Treasury that has not authorised it; `VerifyDeployment` re-checks all
   of it afterwards.

## 2. Deployment graph

```text
1. ProtocolFactory          (constructor also deploys the Registry and the Marketplace implementation)
2. Registry reference       factory.registry()
3. Protocol suite           createProtocolSuite(admin, feeRecipient)
     ├── Treasury
     ├── PaymentManager
     ├── Marketplace (ERC-1967 proxy over the implementation)
     ├── OpenAuction
     ├── DutchAuction
     └── Staking
   ... with payer/creditor wiring, then ownership handed to `admin` (pending acceptance)
4. Controller finalisation  finalizeProtocolSuiteControllers(treasury, paymentManager)
5. Raffle                   createRaffleInstance(...)  — only after VRF configuration is verified
6. VRF subscription         create → register consumer → fund
7. Ownership transfer       transferOwnership(timelock) across the protocol
8. Governance acceptance    schedule batch → wait for delay → execute batch
9. Verification             make verify-deployment
10. Smoke tests             one controlled operation per subsystem
```

Step 4 is irreversible and should be performed in the same release as the ownership handoff, so the
protocol never runs with the Factory as an active controller longer than necessary.

## 3. Layout of `script/`

15 scripts, grouped by responsibility.

### 3.1 Core deployment

| Script | Contracts defined | Purpose |
| --- | --- | --- |
| `Deploy.s.sol` | `DeployScript`, `DeployRaffleScript`, `PrepareOwnershipTransferScript` | Main entry point. Deploys the Factory, optionally the full suite and the Raffle, and prepares the registry/Factory ownership transfer. |

`DeployScript` reads `DEPLOY_FULL_SUITE` and `DEPLOY_RAFFLE` to decide how far to go:

| `DEPLOY_FULL_SUITE` | `DEPLOY_RAFFLE` | Result |
| --- | --- | --- |
| `false` | any | Factory + Registry only |
| `true` | `false` | Factory + Registry + Treasury, PaymentManager, Marketplace, OpenAuction, DutchAuction, Staking → then controller finalisation |
| `true` | `true` | The above plus the Raffle, with full VRF configuration validation |

`DeployRaffleScript` deploys a Raffle against an **already deployed** Factory and Treasury. It requires
`Treasury.factoryController() == FACTORY_ADDRESS` and will fail once controllers have been finalised —
which is the mechanism behind the known limitation in [security.md](security.md#known-design-limitations).

`PrepareOwnershipTransferScript` calls `factory.transferRegistryOwnership(admin)` followed by
`factory.transferOwnership(admin)`. The first call re-registers the Factory as a registrar before the
registry changes hands, so automation discovery keeps working.

### 3.2 Governance

| Script | Purpose |
| --- | --- |
| `DeployGovernance.s.sol` | Deploys `ProtocolTimelock` with `GOVERNANCE_MIN_DELAY`, `GOVERNANCE_PROPOSER`, `GOVERNANCE_EXECUTOR`, `GOVERNANCE_ADMIN` |
| `ConfigureMarketplaceGovernance.s.sol` | Anchors Marketplace `DEFAULT_ADMIN_ROLE` to `GOVERNANCE_TIMELOCK` and assigns `OPERATOR_ROLE` to `GOVERNANCE_OPERATOR` |
| `TransferProtocolOwnership.s.sol` | Calls `transferOwnership(GOVERNANCE_TIMELOCK)` on up to 9 protocols contracts (Factory, Registry, Treasury, PaymentManager, OpenAuction, BlindAuction, DutchAuction, Staking, Raffle); zero addresses are skipped |
| `ScheduleGovernanceOwnershipAcceptance.s.sol` | Schedules `acceptOwnership()` for the same target set as one Timelock batch, with `GOVERNANCE_SALT` and an optional `GOVERNANCE_DELAY` |
| `ExecuteGovernanceOwnershipAcceptance.s.sol` | Executes that batch after the delay |
| `FinalizeProtocolSuite.s.sol` | Calls `factory.finalizeProtocolSuiteControllers(treasury, paymentManager)` |

The split between `TransferProtocolOwnership` and `ScheduleGovernanceOwnershipAcceptance` exists for one
reason: every critical contract is `Ownable2Step`, so a Timelock must schedule its own acceptance. A
timelock-owned `Ownable2Step` contract **cannot** accept ownership through an EOA path.

### 3.3 Chainlink VRF

| Script | Purpose |
| --- | --- |
| `CreateVRFSubscription.s.sol` | Creates a V2.5 subscription on the configured coordinator, optionally funding it with native token (`VRF_NATIVE_FUNDING`) |
| `FundVRFSubscription.s.sol` | Adds funds to an existing subscription |
| `RegisterVRFConsumer.s.sol` | Adds the Raffle as a consumer of the subscription |

### 3.4 Chainlink CRE automation

| Script | Purpose |
| --- | --- |
| `DeployAutomationReceiver.s.sol` | Deploys the production `ProtocolAutomationReceiver` with the real Keystone forwarder, the registry, and the chain selector |
| `DeployAutomationSimulationReceiver.s.sol` | Deploys the simulation receiver; restricted to a known-testnet allowlist (11155111, 84532, 421614, 11155420, 80002, 43113, 97) |
| `ConfigureAutomationReceiver.s.sol` | Sets the workflow id and author, then unpauses the receiver |

### 3.5 Gates and verification

| Script | Purpose |
| --- | --- |
| `Preflight.s.sol` | Read-only pre-broadcast gate. See [preflight.md](preflight.md) |
| `VerifyDeployment.s.sol` | Read-only post-deployment authority graph verification |

## 4. Environment variables by script

Extracted from the scripts themselves; `.env.example` is the authoritative template.

| Script | Variables |
| --- | --- |
| `Deploy.s.sol` | `DEPLOYER_PRIVATE_KEY`, `PROTOCOL_ADMIN`, `FEE_RECIPIENT`, `DEPLOY_FULL_SUITE`, `DEPLOY_RAFFLE`, `FACTORY_ADDRESS`, `TREASURY_ADDRESS`, `VRF_COORDINATOR`, `VRF_SUBSCRIPTION_ID`, `VRF_KEY_HASH`, `VRF_CALLBACK_GAS_LIMIT`, `VRF_REQUEST_CONFIRMATIONS`, `VRF_NATIVE_PAYMENT`, `RAFFLE_FEE_BPS`, `RAFFLE_OWNER` |
| `DeployGovernance.s.sol` | `GOVERNANCE_MIN_DELAY`, `GOVERNANCE_PROPOSER`, `GOVERNANCE_EXECUTOR`, `GOVERNANCE_ADMIN` |
| `ConfigureMarketplaceGovernance.s.sol` | `MARKETPLACE_ADDRESS`, `GOVERNANCE_TIMELOCK`, `PROTOCOL_ADMIN`, `GOVERNANCE_OPERATOR` |
| `TransferProtocolOwnership.s.sol` | `GOVERNANCE_TIMELOCK` plus any of `FACTORY_ADDRESS`, `REGISTRY_ADDRESS`, `TREASURY_ADDRESS`, `PAYMENT_MANAGER_ADDRESS`, `OPEN_AUCTION_ADDRESS`, `BLIND_AUCTION_ADDRESS`, `DUTCH_AUCTION_ADDRESS`, `STAKING_ADDRESS`, `RAFFLE_ADDRESS` |
| `ScheduleGovernanceOwnershipAcceptance.s.sol` | The same address set plus `GOVERNANCE_TIMELOCK`, `GOVERNANCE_SALT`, `GOVERNANCE_DELAY` |
| `ExecuteGovernanceOwnershipAcceptance.s.sol` | The same address set plus `GOVERNANCE_TIMELOCK` |
| `FinalizeProtocolSuite.s.sol` | `FACTORY_ADDRESS`, `TREASURY_ADDRESS`, `PAYMENT_MANAGER_ADDRESS` |
| `CreateVRFSubscription.s.sol` / `FundVRFSubscription.s.sol` | `VRF_COORDINATOR`, `VRF_SUBSCRIPTION_ID` (`Fund` only), `VRF_NATIVE_FUNDING` |
| `RegisterVRFConsumer.s.sol` | `VRF_COORDINATOR`, `VRF_SUBSCRIPTION_ID`, `RAFFLE_ADDRESS` |
| `DeployAutomationReceiver.s.sol` | `DEPLOYER_PRIVATE_KEY`, `AUTOMATION_ADMIN`, `CHAINLINK_FORWARDER`, `PROTOCOL_REGISTRY`, `CHAIN_SELECTOR` |
| `DeployAutomationSimulationReceiver.s.sol` | `DEPLOYER_PRIVATE_KEY`, `AUTOMATION_ADMIN`, `CHAINLINK_MOCK_FORWARDER`, `PROTOCOL_REGISTRY`, `CHAIN_SELECTOR` |
| `ConfigureAutomationReceiver.s.sol` | `AUTOMATION_OWNER_PRIVATE_KEY`, `AUTOMATION_RECEIVER`, `CRE_WORKFLOW_ID`, `CRE_WORKFLOW_AUTHOR` |
| `Preflight.s.sol` | `EXPECTED_CHAIN_ID`, `DEPLOYER_PRIVATE_KEY`, `PROTOCOL_ADMIN`, `FEE_RECIPIENT`, `RAFFLE_FEE_BPS`, `VRF_REQUEST_CONFIRMATIONS` |
| `VerifyDeployment.s.sol` | `FACTORY_ADDRESS`, `PROTOCOL_ADMIN`, `TREASURY_ADDRESS`, `PAYMENT_MANAGER_ADDRESS`, `GOVERNANCE_TIMELOCK`, `MARKETPLACE_ADDRESS`, `FEE_RECIPIENT`, `OPEN_AUCTION_ADDRESS`, `DUTCH_AUCTION_ADDRESS`, `STAKING_ADDRESS`, `GOVERNANCE_OPERATOR`, optional `BLIND_AUCTION_ADDRESS`, optional `RAFFLE_ADDRESS` |

## 5. Contract size gate

Run before any broadcast:

```bash
forge build --sizes
```

Every deployed contract must be under **24,576 bytes** of runtime code (EIP-170) and **49,152 bytes** of
initcode (EIP-3860).

The Factory relies on six external deployer libraries (`CoreDeployer`, `NFTDeployer`, `AuctionDeployer`,
`BlindAuctionDeployer`, `StakingDeployer`, `RaffleDeployer`). `forge script --broadcast` deploys and links
them before the Factory, so a Factory deployment produces **seven contracts to source-verify**, plus the
Registry and Marketplace implementation created inside the Factory's constructor.

## 6. Verification of the deployed authority graph

`make verify-deployment` runs `VerifyDeployment.s.sol`, which aborts with a distinct
`DeploymentMismatch(<check>)` for each of the following:

| Check | Expectation |
| --- | --- |
| `zero-config` | `PROTOCOL_ADMIN`, `GOVERNANCE_TIMELOCK`, `MARKETPLACE_ADDRESS` all set |
| `admin-timelock` | `PROTOCOL_ADMIN == GOVERNANCE_TIMELOCK` |
| `factory-owner` / `registry-owner` | Both owned by the admin |
| `treasury-owner` / `payment-owner` | Both owned by the admin |
| `fee-recipient` | Treasury's fee recipient equals `FEE_RECIPIENT` |
| `factory-registrar` | Factory is still an authorised registrar on the registry |
| `treasury-controller` / `payment-controller` | Both `factoryController` values are `address(0)` |
| `marketplace-payer`, `open-auction-payer`, `blind-auction-payer`, `dutch-auction-payer`, `staking-payer` | Each is authorised on the Treasury |
| `marketplace-creditor` | Marketplace is an authorised creditor on the PaymentManager |
| `open-auction-owner`, `blind-auction-owner`, `dutch-auction-owner`, `staking-owner`, `raffle-owner` | Each owned by the Timelock |
| `marketplace-governance` | Marketplace `DEFAULT_ADMIN_ROLE` held by the Timelock |
| `marketplace-operator` | `GOVERNANCE_OPERATOR`, when set, holds `OPERATOR_ROLE` |
| `marketplace-treasury` / `marketplace-payment-manager` | The Marketplace points at the verified addresses |

This script is the machine-checkable half of the release. The human half is the checklist in
[mainnet.md](mainnet.md).

## 7. Post-deployment smoke tests

A deployment is not complete until each subsystem has executed one controlled operation on-chain:

| Subsystem | Smoke test |
| --- | --- |
| CustomNFT | Mint a token |
| Marketplace | List and buy that token through a second account |
| OpenAuction | Create, bid, finalise |
| BlindAuction | Commit, reveal, finalise |
| DutchAuction | Create, buy below start price, verify the excess refund |
| Staking | Stake, claim, unstake |
| Raffle | Create with a test NFT, buy a ticket, request randomness, verify fulfillment |
| Treasury | Withdraw a claimable balance as the seller |
| Automation | One end-to-end CRE report delivered through the forwarder |

## 8. Deployment anti-patterns

| Anti-pattern | Why it is wrong |
| --- | --- |
| Broadcasting without `make preflight` | The preflight script is the only automated check of chain id, deployer, and configuration |
| Deploying the Raffle before verifying the target-chain VRF configuration | The constructor validates shapes, not addresses; a wrong-but-valid coordinator is accepted |
| Finalising controllers before ownership handoff | Leaves the protocol unsupervised in the interim |
| Accepting ownership for a Timelock through an EOA script | Impossible for a correct `Ownable2Step` flow and a sign of a wrong assumption |
| Deploying `ProtocolAutomationSimulationReceiver` on mainnet | It accepts reports without workflow identity; the deployment script blocks known-mainnet ids but the check is a guard, not a permission |
| Reusing a CREATE2 salt | The Factory rejects it for `createCustomNFTDeterministic` |
| Committing a populated `.env` | `.gitignore` excludes it; committing it is a key-disclosure incident |

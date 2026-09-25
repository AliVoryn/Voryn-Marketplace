# Mainnet Deployment Checklist

This is a release **procedure**, not a security guarantee. Complete it on a clean checkout, from a reviewed
commit, with a second operator reviewing every production configuration value before broadcast.

A mainnet deployment is not operationally complete until **all** of the following have succeeded on-chain:
source verification, ownership acceptance, factory-controller finalisation, governance verification,
VRF consumer registration, and post-deployment smoke checks.

Related documents: [deployment.md](deployment.md) (mechanics and script reference),
[preflight.md](preflight.md) (the pre-broadcast gate), [raffle-mainnet.md](raffle-mainnet.md) (VRF
specifics), [security.md](security.md) (trust model and known limitations).

---

## 1. Release gates

| Gate | Command | Blocking |
| --- | --- | --- |
| Clean checkout at a reviewed commit | `git status --porcelain` (empty) | Yes |
| Pinned dependencies installed and verified | `git submodule update --init --recursive` | Yes |
| Contract size | `forge build --sizes` | Yes |
| Full test suite | `forge test` | Yes |
| Fuzz at CI profile | `FOUNDRY_PROFILE=ci forge test --match-test 'testFuzz_'` | Yes |
| Invariants at CI profile | `FOUNDRY_PROFILE=ci forge test --match-test 'invariant_'` | Yes |
| Static analysis | `forge lint` | Yes |
| Fork gate | `forge test --match-path 'test/**/*.Fork.t.sol' -vvvv` (`RPC_URL` required) | Yes |
| Environment gate | `forge script script/Preflight.s.sol --rpc-url "$RPC_URL"` | Yes |
| Authority graph after deployment | `forge script script/VerifyDeployment.s.sol --rpc-url "$RPC_URL"` | Yes |
| External security review | out of band | Yes, before broadcast |
| Second-operator review of every configuration value | out of band | Yes |

## 2. Toolchain and provenance

- Pin Foundry to **v1.8.3**.
- Pin Solidity to **0.8.24**.
- Initialize the pinned `forge-std` submodule with `git submodule update --init --recursive`.
- **Record the repository commit used for deployment.** A deployment whose commit is unknown cannot be
  reproduced or verified.
- Build from a clean checkout.
- Do not include `.env`, private keys, RPC credentials, API keys, or generated `out/` and `cache/`
  directories in the release commit.

## 3. Contract size gate

```bash
forge build --sizes
```

Every deployed contract must be below **24,576 bytes** of runtime code and **49,152 bytes** of initcode.

The Factory relies on six external deployer libraries (`CoreDeployer`, `NFTDeployer`, `AuctionDeployer`,
`BlindAuctionDeployer`, `StakingDeployer`, `RaffleDeployer`). `forge script --broadcast` deploys and links
them before the Factory, so a Factory deployment produces **seven contracts to source-verify**, plus the
Registry and the Marketplace implementation created inside the Factory constructor.

## 4. Preflight

```bash
export EXPECTED_CHAIN_ID=<chain id>
export DEPLOYER_PRIVATE_KEY=<key>       # read only; preflight never signs
export PROTOCOL_ADMIN=<timelock>
export FEE_RECIPIENT=<recipient>
forge script script/Preflight.s.sol --rpc-url "$RPC_URL"
```

The protocol-admin target for a governance-controlled release **is** the deployed Timelock address.

**Do not broadcast** if the chain id, deployer, governance target, fee recipient, VRF configuration, or
network RPC is unexpected. See [preflight.md](preflight.md) for the failure playbook.

## 5. Governance deployment

1. Deploy `ProtocolTimelock` with the intended minimum delay and proposer set
   (`DeployGovernance.s.sol`). Use an explicit executor when required, or the zero address to allow open
   execution after the delay.
2. Prefer `GOVERNANCE_ADMIN=0x0000000000000000000000000000000000000000` for a no-bootstrap-admin
   configuration, or use a separately reviewed setup multisig and remove its privilege after setup.
3. Set `PROTOCOL_ADMIN = GOVERNANCE_TIMELOCK` for a fully governance-controlled protocol release.

## 6. Protocol deployment

1. Deploy the Factory (`DeployScript` with `DEPLOY_FULL_SUITE=false`), or the Factory and the full suite in
   one run (`DEPLOY_FULL_SUITE=true`).
2. Verify the Factory and Registry addresses from the broadcast output.
3. Deploy the full protocol suite with `PROTOCOL_ADMIN=GOVERNANCE_TIMELOCK`.
4. The full-suite deployment finalises Treasury and PaymentManager factory controllers before ownership
   handoff. This prevents the governance-controlled suite from retaining factory bootstrap authority after
   release.
5. Deploy the Raffle **only after** the target-chain Chainlink VRF configuration has been independently
   verified ([raffle-mainnet.md](raffle-mainnet.md) §1).
6. Register the Raffle as a VRF subscription consumer using the subscription owner account.
7. Fund the VRF subscription using the selected payment mode and verify the resulting balance and
   configuration.
8. Prepare ownership transfers from the deployer to `GOVERNANCE_TIMELOCK`
   (`TransferProtocolOwnership.s.sol`; `PrepareOwnershipTransferScript` in `Deploy.s.sol` handles the
   Factory and Registry).
9. Schedule the `acceptOwnership()` calls through the Timelock
   (`ScheduleGovernanceOwnershipAcceptance.s.sol`).
10. After the configured delay, execute the batch
    (`ExecuteGovernanceOwnershipAcceptance.s.sol`).
11. Run `forge script script/VerifyDeployment.s.sol --rpc-url "$RPC_URL"` against the live deployment.

Steps 8–10 exist because every critical contract uses two-step ownership. A Timelock **cannot** accept
ownership from an EOA-signed transaction; the acceptance must itself be a scheduled Timelock operation.

## 7. Ownership and authority

The production target is explicit:

| Contract | Target state |
| --- | --- |
| Factory, Registry | Owned by the Timelock; Factory retains registrar rights on the Registry |
| Treasury, PaymentManager | Owned by the Timelock; `factoryController == address(0)` |
| OpenAuction, DutchAuction, Staking, Raffle | Owned by the Timelock |
| Marketplace | `DEFAULT_ADMIN_ROLE` on the Timelock; `OPERATOR_ROLE` assigned deliberately and verified on-chain |
| Automation receiver | Owned by the Timelock or a dedicated, reviewed automation admin |

The direct `AcceptEOAProtocolOwnershipScript` path is for an **EOA final owner only**. Do not use it to
accept ownership for a Timelock.

## 8. External contracts

- Verify every target-chain Chainlink address against current official deployment documentation before
  broadcast.
- Verify the coordinator contract has code at the expected address.
- Verify subscription id, key hash, callback gas limit, request confirmations, payment mode, and consumer
  registration.
- Verify the selected chain id and RPC endpoint.
- Verify explorer configuration before source verification.
- Verify the Keystone forwarder address before deploying the automation receiver — the receiver's trust in
  that address is the entire basis of report authenticity.

## 9. Protocol state after handoff

`forge script script/VerifyDeployment.s.sol --rpc-url "$RPC_URL"` checks all of the following automatically; this list is the human-readable
counterpart, and it is also the list to walk manually if the script cannot run.

- Factory owner, and Factory registrar status on the Registry.
- Registry owner.
- Treasury owner, fee recipient, factory controller, authorized payers, and liabilities.
- PaymentManager owner, factory controller, and authorized creditors.
- Marketplace default admin and operator roles.
- Auction and Staking owners.
- Raffle owner and VRF configuration.
- Upgrade authorization (Marketplace `DEFAULT_ADMIN_ROLE`).
- Pause authorities.
- No unexpected privileged account retains a critical role.

## 10. Governance

`ProtocolTimelock` is a control plane **only** where target contracts are actually owned or administered by
it. For this repository's mainnet flow:

```text
PROTOCOL_ADMIN == GOVERNANCE_TIMELOCK
ownership acceptance executes through the Timelock after its minimum delay
```

Critical future changes follow the same path: a proposer schedules, the minimum delay elapses, an executor
executes, and the resulting authority and state are verified. Any privileged change that bypasses this path
should be treated as an incident.

## 11. Known design limitations

These are documented in full, with consequences and the decision each one requires, in
[security.md](security.md#known-design-limitations). Summary:

| Limitation | Mainnet impact |
| --- | --- |
| `createBlindAuctionInstance` cannot grant payer rights after controller finalisation | Decide before mainnet whether BlindAuction is in scope or needs a different authorisation design |
| Offer refunds (`cancelOffer`, `expireOffer`) are blocked while the Marketplace is paused | Pausing freezes buyer escrow; treat pausing as an economic decision |
| Pausing a `CustomNFT` collection freezes transfers | A paused collection cannot settle auctions, raffles, or listings that escrow its tokens |
| A stuck raffle can only be cancelled by its creator after the delay | Liveness depends on creator availability |

## 12. Verification and monitoring

- Verify implementations and proxies on the chosen explorer.
- Record deployment transaction hashes and block numbers.
- Run read-only state checks with `cast`.
- Run controlled post-deployment smoke tests for every deployed subsystem
  ([deployment.md](deployment.md#7-post-deployment-smoke-tests)).
- Confirm monitoring for critical events, failed external calls, VRF callbacks, and governance operations.
- Confirm alerting on `ProtocolAutomationReceiver` failures — a silently failing automation layer is
  invisible until users notice stuck auctions or offers.

## 13. Operational safety

- Do not broadcast deployment transactions until configuration values have been reviewed by a second
  operator.
- Never commit `.env` files or private keys.
- Do not treat a passing unit or invariant suite as a substitute for an external security audit or live
  dependency verification.
- If `forge script script/VerifyDeployment.s.sol --rpc-url "$RPC_URL"` fails any check, treat the deployment as failed: fix the configuration,
  redeploy to a fresh address set, and do not patch around it with manual transactions.

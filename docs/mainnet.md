# Mainnet Deployment Checklist

## Release gates

This checklist is a release procedure, not a security guarantee. Complete it on a clean checkout, from a reviewed commit, with a second operator reviewing all production configuration before broadcast.

A mainnet deployment is not considered operationally complete until source verification, ownership acceptance, factory-controller finalization, governance verification, VRF consumer registration, and post-deployment smoke checks have all succeeded on-chain.

## Toolchain and provenance

- Pin Foundry to v1.8.3.
- Pin Solidity to 0.8.24.
- Install dependencies from `script/install-dependencies.sh`.
- Record the repository commit used for deployment.
- Build from a clean checkout.
- Do not include `.env`, private keys, RPC credentials, API keys, or generated `out/` and `cache/` directories in the release commit.

## Contract size gate

Run `forge build --sizes` before any broadcast. Every deployed contract must be below 24,576 bytes of runtime code and 49,152 bytes of initcode. The Factory relies on six external deployer libraries (`CoreDeployer`, `NFTDeployer`, `AuctionDeployer`, `BlindAuctionDeployer`, `StakingDeployer`, `RaffleDeployer`); `forge script --broadcast` deploys and links them before the Factory, so a Factory deployment produces seven contracts to source-verify (plus the Registry and Marketplace implementation created in the Factory constructor).

## Preflight

Run `make preflight` with an explicit `EXPECTED_CHAIN_ID`, deployer, protocol admin, and fee recipient. The protocol-admin target for a governance-controlled release should be the deployed timelock address.

Do not broadcast if the chain ID, deployer, governance target, fee recipient, VRF configuration, or network RPC is unexpected.

## Governance deployment

1. Deploy `ProtocolTimelock` with the intended minimum delay and proposer. Use an explicit executor when required, or the zero address to allow open execution after the delay.
2. Prefer `GOVERNANCE_ADMIN=0x0000000000000000000000000000000000000000` for a no-bootstrap-admin configuration, or use a separately reviewed setup multisig and remove its privilege after setup.
3. Set `PROTOCOL_ADMIN` equal to `GOVERNANCE_TIMELOCK` for a fully governance-controlled protocol release.

## Protocol deployment

1. Deploy the Factory.
2. Verify the Factory and Registry addresses from the broadcast output.
3. Deploy the full protocol suite with `PROTOCOL_ADMIN=GOVERNANCE_TIMELOCK`.
4. The full-suite deployment finalizes Treasury and PaymentManager factory controllers before ownership handoff. This prevents the governance-controlled suite from retaining factory bootstrap authority after release.
5. Deploy the Raffle only after the target-chain Chainlink VRF configuration has been independently verified.
6. Register the Raffle as a VRF subscription consumer using the subscription owner account.
7. Fund the VRF subscription using the selected payment mode and verify the resulting balance/configuration.
8. Prepare ownership transfers from the deployer to `GOVERNANCE_TIMELOCK`.
9. Schedule the `acceptOwnership()` calls through the Timelock using `ScheduleGovernanceOwnershipAcceptance.s.sol`.
10. After the configured delay, execute the batch through the Timelock using `ExecuteGovernanceOwnershipAcceptance.s.sol`.
11. Run `make verify-deployment` against the live deployment.

## Ownership and authority

The production target is explicit: critical Ownable contracts are owned by the Timelock, while Treasury and PaymentManager factory controllers are finalized to zero. Marketplace governance is anchored to the Timelock's `DEFAULT_ADMIN_ROLE`; the operator role is assigned deliberately and verified on-chain when configured.

The direct `AcceptEOAProtocolOwnershipScript` path is for an EOA final owner only. Do not use it to accept ownership for a Timelock. A Timelock-owned `Ownable2Step` contract must accept ownership through a scheduled Timelock operation.

## External contracts

- Verify every target-chain Chainlink address against current official deployment documentation before broadcast.
- Verify the coordinator contract has code at the expected address.
- Verify subscription ID, key hash, callback gas limit, request confirmations, payment mode, and consumer registration.
- Verify the selected chain ID and RPC endpoint.
- Verify explorer configuration before source verification.

## Protocol state

After ownership handoff, verify at minimum:

- Factory owner.
- Registry owner and Factory registrar relationship.
- Treasury owner, fee recipient, factory controller, authorized payers, and liabilities.
- PaymentManager owner, factory controller, and authorized creditors.
- Marketplace default admin and operator roles.
- Auction and Staking owners.
- Raffle owner and VRF configuration.
- Upgrade authorization.
- Pause authorities.
- No unexpected privileged account retaining critical roles.

## Governance

`ProtocolTimelock` is the control plane only when target contracts are actually owned or administered by it. For this repository's mainnet flow, `PROTOCOL_ADMIN` should equal `GOVERNANCE_TIMELOCK`, and the ownership acceptance must execute through the Timelock after its minimum delay.

Critical future changes should follow the same control path: proposer schedules, the minimum delay elapses, executor executes, and resulting authority/state is verified.

## Known design limitations

- After `finalizeProtocolSuiteControllers` the Factory can no longer authorize new Treasury payers. `createBlindAuctionInstance` (one contract per NFT) therefore cannot be used against the finalized protocol Treasury; each new BlindAuction would need a Timelock operation calling `Treasury.setAuthorizedPayer`. Decide before mainnet whether BlindAuction is in scope or needs a different authorization design.
- Sellers and owners of OpenAuction/BlindAuction can cancel an auction while bids are live (bidders are refunded). Marketplace offer refunds (`cancelOffer`, `expireOffer`) are blocked while the Marketplace is paused.
- The whole tree needs one `forge fmt` pass; `forge fmt --check` in CI will fail until it is run.

## Verification and monitoring

- Verify implementations and proxies on the chosen explorer.
- Record deployment transaction hashes and block numbers.
- Run read-only state checks with `cast`.
- Run controlled post-deployment smoke tests for every deployed subsystem.
- Confirm monitoring for critical events, failed external calls, VRF callbacks, and governance operations.

## Operational safety

Do not broadcast deployment transactions until configuration values are reviewed by a second operator. Never commit `.env` files or private keys. Do not treat a passing unit/invariant suite as a substitute for an external security audit or live dependency verification.

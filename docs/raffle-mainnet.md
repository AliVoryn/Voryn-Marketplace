# Raffle Mainnet Operations

## Required configuration

- Target chain ID
- VRF coordinator for the target chain
- VRF subscription ID
- VRF key hash / gas lane
- callback gas limit
- request confirmations
- native or LINK payment mode
- raffle owner
- Treasury address

## Callback gas

`rawFulfillRandomWords` finalizes the raffle inside the VRF callback: it credits the Treasury twice and transfers the NFT. If the callback runs out of gas the coordinator does not retry it, the raffle stays in `AwaitingRandomness`, and only the creator can cancel it after the stuck-raffle delay. The repository default is 500000. `Raffle.Integration` logs the measured fulfillment gas (`raffle fulfillment gas`); repeat that measurement on a fork with the real NFT collection and keep the configured limit well above it.

## Sequence

1. Verify the current Chainlink VRF V2.5 deployment and configuration for the target chain from official Chainlink documentation.
2. Create or provision the VRF subscription from the intended subscription owner.
3. Deploy the Raffle with the exact target-chain coordinator and subscription configuration.
4. Add the Raffle contract as a consumer of the subscription.
5. Fund the subscription according to the selected payment mode.
6. Verify the Raffle configuration on-chain.
7. Create a controlled raffle using a test NFT.
8. Complete a full request and fulfillment cycle.
9. Confirm winner transfer, proceeds, fees, and raffle escrow invariants.
10. Record the subscription ID, consumer address, deployment transaction, and resulting configuration.

## Dependency policy

The repository uses the Foundry installation path for Chainlink EVM contracts and pins `contracts-v1.5.0`. The imported VRF interfaces are under Chainlink's `dev` source namespace; treat the exact upstream release, deployed coordinator compatibility, and target-chain addresses as release-gate inputs. Do not substitute a development or nightly dependency without an explicit review.

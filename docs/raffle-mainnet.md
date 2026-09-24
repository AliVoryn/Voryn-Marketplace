# Raffle — Chainlink VRF Operations

Operational reference for the raffle's Chainlink VRF V2.5 integration: what must be configured, what the
gas limit has to cover, the deployment sequence, and the dependency policy.

Related: [mainnet.md](mainnet.md) (full release runbook), [contracts.md](contracts.md#raffle)
(contract reference), [AUTOMATION.md](AUTOMATION.md) (automated winner requests and refund batching).

---

## 1. Required configuration

| Parameter | Source | Validated by |
| --- | --- | --- |
| Target chain ID | deployment plan | `Raffle` has no chain check; the preflight gate does |
| VRF coordinator | target-chain Chainlink documentation | Must have code — `Raffle._validateVRFConfig` |
| VRF subscription ID | created or provisioned on-chain | Must be non-zero |
| VRF key hash / gas lane | target-chain Chainlink documentation | Must be non-zero |
| Callback gas limit | measured for your collection | Must be non-zero; repository default `500000` |
| Request confirmations | target-chain guidance | Must be in `[3, 200]` |
| Payment mode | native or LINK | Set by `nativePayment`; `VRF_V2PlusClient.ExtraArgsV1` |
| Raffle owner | governance plan | Set at construction |
| Treasury address | deployed Treasury | Must have code |

Configuration cannot be set to an invalid combination: the constructor and `setVRFConfig` apply the same
`_validateVRFConfig` rules, so an invalid configuration is rejected rather than stored and discovered later.

## 2. Callback gas

`rawFulfillRandomWords` finalises the raffle **inside the VRF callback**. In one call it:

1. validates the coordinator identity and the request binding,
2. computes the winning ticket index and resolves the entrant by binary search,
3. splits proceeds between the fee recipient and the creator,
4. credits the Treasury twice,
5. transfers the NFT to the winner,
6. asserts the raffle escrow invariant.

If the callback runs out of gas, the coordinator **does not retry**. The raffle stays in
`AwaitingRandomness`, and only the creator can cancel it after the 24-hour stuck-raffle delay.

The repository default is `VRF_CALLBACK_GAS_LIMIT=500000`. `Raffle.Integration` logs the measured
fulfillment gas under the label `raffle fulfillment gas`.

**Procedure:**

```bash
forge test --match-path 'test/raffle/Raffle.Integration.t.sol' -vv   # read the measured value
```

Then repeat the measurement on a fork with the **real NFT collection** you intend to raffle, and keep the
configured limit well above the measured cost. An ERC-721 with expensive transfer hooks or a large
`tokenURI` can cost meaningfully more than a minimal test token.

## 3. Deployment sequence

1. Verify the current Chainlink VRF V2.5 deployment and configuration for the target chain from official
   Chainlink documentation.
2. Create or provision the VRF subscription from the intended subscription owner
   (`CreateVRFSubscription.s.sol`).
3. Deploy the Raffle with the exact target-chain coordinator and subscription configuration
   (`Deploy.s.sol` with `DEPLOY_RAFFLE=true`, or `DeployRaffleScript` against an existing Factory).
4. Add the Raffle as a consumer of the subscription (`RegisterVRFConsumer.s.sol`).
5. Fund the subscription according to the selected payment mode (`FundVRFSubscription.s.sol`).
6. Verify the Raffle configuration on-chain.
7. Create a controlled raffle using a test NFT.
8. Complete a full request and fulfilment cycle.
9. Confirm winner transfer, proceeds, fees, and the raffle escrow invariant.
10. Record the subscription ID, consumer address, deployment transaction, and resulting configuration.

> **Ordering constraint.** Step 3 requires `Treasury.factoryController() == FACTORY_ADDRESS`. Once
> `finalizeProtocolSuiteControllers` has been called, `createRaffleInstance` reverts. Deploy the Raffle
> **before** finalising the controllers, then finalise as part of the same release.

## 4. Operating a live raffle

| Situation | Path |
| --- | --- |
| Raffle sold out | Anyone can call `requestRandomWinner` — the CRE workflow does it automatically once the candidate appears |
| End time passed with tickets sold | Anyone can call `requestRandomWinner` |
| End time passed with no tickets | Anyone can call `finalizeFailedRaffle`; the NFT returns to the creator |
| Randomness requested, no callback | After `RANDOMNESS_RETRY_DELAY` (1 hour) the **owner** can call `retryRandomWinnerRequest` — this is deliberately not in the automation allowlist |
| Still nothing after 24 hours | The **creator** can call `cancelStuckRaffle`; tickets then become refundable |
| Cancelled with entrants | `processRaffleRefunds` batches 1–100 entrants per call; the CRE workflow drives it with the on-chain cursor; buyers claim with `claimRaffleRefund` |

Monitoring that matters: `RandomnessRequested` without a matching `RaffleFinalized`, and the raffle's
`phase` staying at `AwaitingRandomness` past one hour.

## 5. Dependency policy

The repository uses the Foundry installation path for Chainlink EVM contracts and pins
**`contracts-v1.5.0`** via `script/install-dependencies.sh`.

The imported VRF interfaces live under Chainlink's `dev` source namespace:

```solidity
import { VRFV2PlusClient } from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";
import { IVRFCoordinatorV2Plus } from "@chainlink/contracts/src/v0.8/vrf/dev/interfaces/IVRFCoordinatorV2Plus.sol";
```

Treat the exact upstream release, deployed coordinator compatibility, and target-chain addresses as
**release-gate inputs**, not as implementation details. Do not substitute a development or nightly
dependency without an explicit review.

> **Repository note.** The committed `lib/` tree contains both `lib/chainlink-evm` (used — resolved by the
> `@chainlink/` remapping) and `lib/chainlink` (unused — nothing in `src/` or `test/` imports it). Only
> `chainlink-evm` participates in the build. This is a packaging artefact of dependency installation, not a
> dual-dependency design.

## 6. Pre-launch checklist

- [ ] Coordinator address verified against official Chainlink documentation for the target chain
- [ ] Coordinator address has code
- [ ] Subscription ID recorded and owned by the intended account
- [ ] Key hash / gas lane verified for the target chain
- [ ] `VRF_REQUEST_CONFIRMATIONS` within `[3, 200]` and consistent with chain guidance
- [ ] `VRF_CALLBACK_GAS_LIMIT` measured against the real NFT collection and set comfortably above it
- [ ] Payment mode decided (native vs LINK) and funded accordingly
- [ ] Raffle registered as a subscription consumer
- [ ] Raffle owner set to the Timelock
- [ ] One full request/fulfilment cycle completed on a testnet
- [ ] A full request/fulfilment cycle completed on a fork of the target chain
- [ ] Monitoring in place for requests without fulfilments
- [ ] The stuck-raffle operator (creator) is reachable, or §7.4 of [security.md](security.md) has been
      explicitly accepted

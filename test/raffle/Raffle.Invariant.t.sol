// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import "forge-std/StdInvariant.sol";

import "../support/TestBase.sol";

contract RaffleInvariantHandler is Test {
    Raffle internal raffle;
    CustomNFT internal nft;
    MockVRFCoordinatorV2Plus internal coordinator;
    uint256 public raffleId;
    uint256 public tokenId;

    receive() external payable { }

    constructor(Raffle raffle_, CustomNFT nft_, MockVRFCoordinatorV2Plus coordinator_) {
        raffle = raffle_;
        nft = nft_;
        coordinator = coordinator_;
    }

    function createRaffleIfNeeded() external {
        if (raffleId != 0) {
            IRaffle.RaffleData memory current = raffle.getRaffle(raffleId);
            if (
                current.phase != IRaffle.RafflePhase.Finalized && current.phase != IRaffle.RafflePhase.Cancelled
                    && current.phase != IRaffle.RafflePhase.Failed
            ) return;
        }
        tokenId = nft.mint(address(this), "ipfs://raffle");
        nft.approve(address(raffle), tokenId);
        raffleId = raffle.createRaffle(address(nft), tokenId, 0.1 ether, 10, 10, 0, 1 days);
    }

    function buyTickets(uint256 quantitySeed) external {
        if (raffleId == 0) return;
        IRaffle.RaffleData memory current = raffle.getRaffle(raffleId);
        if (current.phase != IRaffle.RafflePhase.Active || block.timestamp >= current.endAt) return;
        uint256 remaining = current.maxTickets == 0 ? 5 : current.maxTickets - current.ticketsSold;
        if (remaining == 0) return;
        uint256 quantity = bound(quantitySeed, 1, remaining > 5 ? 5 : remaining);
        uint256 cost = quantity * current.ticketPrice;
        vm.deal(address(this), cost);
        try raffle.buyTickets{ value: cost }(raffleId, quantity) { } catch { }
    }

    function requestRandomness() external {
        if (raffleId == 0) return;
        try raffle.requestRandomWinner(raffleId) { } catch { }
    }

    function fulfill(uint256 randomWordSeed) external {
        if (raffleId == 0) return;
        IRaffle.RaffleData memory current = raffle.getRaffle(raffleId);
        if (current.phase != IRaffle.RafflePhase.AwaitingRandomness) return;
        coordinator.fulfillSingle(current.vrfRequestId, randomWordSeed);
    }

    function cancelStuck() external {
        if (raffleId == 0) return;
        IRaffle.RaffleData memory current = raffle.getRaffle(raffleId);
        if (current.phase != IRaffle.RafflePhase.AwaitingRandomness) return;
        vm.warp(uint256(current.randomnessRequestedAt) + raffle.STUCK_RAFFLE_CANCEL_DELAY());
        try raffle.cancelStuckRaffle(raffleId) { } catch { }
    }

    function processRefunds() external {
        if (raffleId == 0) return;
        try raffle.processRaffleRefunds(raffleId, 10) { } catch { }
    }

    function claimRefund() external {
        try raffle.claimRaffleRefund() { } catch { }
    }

    function warp(uint256 secondsSeed) external {
        vm.warp(block.timestamp + bound(secondsSeed, 1, 1 days));
    }
}

contract RaffleInvariantTest is ProtocolTestBase {
    Raffle internal raffle;
    RaffleInvariantHandler internal handler;
    MockVRFCoordinatorV2Plus internal coordinator;

    function setUp() public {
        _setUpCore();
        coordinator = _deployMockCoordinator();
        raffle = _deployRaffle(address(treasury), coordinator);
        vm.prank(admin);
        treasury.setAuthorizedPayer(address(raffle), true);
        handler = new RaffleInvariantHandler(raffle, nft, coordinator);
        vm.prank(admin);
        nft.grantMinter(address(handler));
        targetContract(address(handler));
    }

    function invariant_RaffleEscrowNeverExceedsBalance() public view {
        uint256 reserved = raffle.totalActiveRaffleFunds() + raffle.totalRaffleRefundLiability();
        assertGe(address(raffle).balance, reserved);
    }
}

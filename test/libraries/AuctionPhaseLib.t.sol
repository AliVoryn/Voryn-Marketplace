// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import "forge-std/Test.sol";
import "../../src/libraries/AuctionPhaseLib.sol";
import "../../src/interfaces/IBlindAuction.sol";

contract AuctionPhaseLibHarness {
    using AuctionPhaseLib for AuctionPhaseLib.Clock;
    AuctionPhaseLib.Clock public clock;

    function setClock(uint256 biddingEnd, uint256 revealEnd) external {
        clock.biddingEnd = biddingEnd;
        clock.revealEnd = revealEnd;
        clock.revealExtensionsUsed = 0;
        clock.ended = false;
        clock.cancelled = false;
    }

    function phase() external view returns (IBlindAuction.Phase) {
        return clock.currentPhase();
    }

    function tryExtend(uint256 window, uint256 extension, uint256 maxExt) external returns (bool) {
        return clock.tryExtendReveal(window, extension, maxExt);
    }

    function setCancelled(bool v) external {
        clock.cancelled = v;
    }

    function setEnded(bool v) external {
        clock.ended = v;
    }

    function requirePhase(IBlindAuction.Phase required) external view {
        clock.requirePhase(required);
    }

    function timeRemaining() external view returns (uint256) {
        return clock.timeRemaining();
    }
}

contract AuctionPhaseLibTest is Test {
    AuctionPhaseLibHarness internal harness;

    function setUp() public {
        harness = new AuctionPhaseLibHarness();
    }

    function test_currentPhase_BiddingBeforeBiddingEnd() public {
        harness.setClock(block.timestamp + 100, block.timestamp + 200);
        assertEq(uint8(harness.phase()), uint8(IBlindAuction.Phase.Bidding));
    }

    function test_currentPhase_RevealAfterBiddingEnd() public {
        harness.setClock(block.timestamp + 1, block.timestamp + 200);
        vm.warp(block.timestamp + 2);
        assertEq(uint8(harness.phase()), uint8(IBlindAuction.Phase.Reveal));
    }

    function test_currentPhase_AwaitingFinalizationAfterRevealEnd() public {
        harness.setClock(block.timestamp + 1, block.timestamp + 2);
        vm.warp(block.timestamp + 3);
        assertEq(uint8(harness.phase()), uint8(IBlindAuction.Phase.AwaitingFinalization));
    }

    function test_tryExtendReveal_ExtendsInsideWindow() public {
        harness.setClock(block.timestamp + 1, block.timestamp + 10);
        vm.warp(block.timestamp + 2);
        bool extended = harness.tryExtend(50, 20, 3);
        assertTrue(extended);
    }

    function test_tryExtendReveal_NoExtendOutsideWindow() public {
        harness.setClock(block.timestamp + 1, block.timestamp + 1000);
        vm.warp(block.timestamp + 2);
        bool extended = harness.tryExtend(5, 20, 3);
        assertFalse(extended);
    }

    function test_tryExtendReveal_RespectsMaxExtensions() public {
        harness.setClock(block.timestamp + 1, block.timestamp + 10);
        vm.warp(block.timestamp + 9);
        assertTrue(harness.tryExtend(50, 5, 1));
        assertFalse(harness.tryExtend(50, 5, 1));
    }

    function test_currentPhase_CancelledTakesPriorityOverTime() public {
        harness.setClock(block.timestamp + 100, block.timestamp + 200);
        harness.setCancelled(true);
        assertEq(uint8(harness.phase()), uint8(IBlindAuction.Phase.Cancelled));
    }

    function test_currentPhase_EndedTakesPriorityOverCancelledCheckOrder() public {
        harness.setClock(block.timestamp + 100, block.timestamp + 200);
        harness.setEnded(true);
        assertEq(uint8(harness.phase()), uint8(IBlindAuction.Phase.Ended));
    }

    function test_requirePhase_PassesWhenMatching() public {
        harness.setClock(block.timestamp + 100, block.timestamp + 200);
        harness.requirePhase(IBlindAuction.Phase.Bidding);
    }

    function test_requirePhase_RevertsWhenMismatched() public {
        harness.setClock(block.timestamp + 100, block.timestamp + 200);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBlindAuction.InvalidPhase.selector, IBlindAuction.Phase.Bidding, IBlindAuction.Phase.Reveal
            )
        );
        harness.requirePhase(IBlindAuction.Phase.Reveal);
    }

    function test_timeRemaining_DuringBidding() public {
        harness.setClock(block.timestamp + 100, block.timestamp + 200);
        assertEq(harness.timeRemaining(), 100);
    }

    function test_timeRemaining_DuringReveal() public {
        harness.setClock(block.timestamp + 1, block.timestamp + 50);
        vm.warp(block.timestamp + 2);
        assertEq(harness.timeRemaining(), 48);
    }

    function test_timeRemaining_ZeroAfterAwaitingFinalization() public {
        harness.setClock(block.timestamp + 1, block.timestamp + 2);
        vm.warp(block.timestamp + 3);
        assertEq(harness.timeRemaining(), 0);
    }

    function test_tryExtendReveal_FalseExactlyAtWindowBoundary() public {
        harness.setClock(block.timestamp + 1, block.timestamp + 10);
        vm.warp(block.timestamp);
        assertFalse(harness.tryExtend(9, 5, 3));
    }

    function test_tryExtendReveal_FalseWhenRevealAlreadyEnded() public {
        harness.setClock(block.timestamp + 1, block.timestamp + 2);
        vm.warp(block.timestamp + 5);
        assertFalse(harness.tryExtend(1000, 5, 3));
    }
}

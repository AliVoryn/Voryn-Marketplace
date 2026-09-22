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
}

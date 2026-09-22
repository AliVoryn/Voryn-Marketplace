pragma solidity ^0.8.24;
import "forge-std/Test.sol";
import "../../src/libraries/AuctionMath.sol";
contract AuctionMathTest is Test {
    function test_nextMinimumBid() public pure {
        assertEq(AuctionMath.nextMinimumBid(1 ether, 0.1 ether), 1.1 ether);
    }
    function test_shouldExtend_FalseWhenExtensionsExhausted() public view {
        assertFalse(AuctionMath.shouldExtend(uint64(block.timestamp), uint64(block.timestamp + 1), 10, 3, 3));
    }
    function test_shouldExtend_FalseWhenAlreadyPastEnd() public view {
        assertFalse(AuctionMath.shouldExtend(uint64(block.timestamp + 10), uint64(block.timestamp), 10, 0, 3));
    }
    function test_shouldExtend_TrueInsideWindow() public view {
        assertTrue(AuctionMath.shouldExtend(uint64(block.timestamp), uint64(block.timestamp + 5), 10, 0, 3));
    }
    function test_shouldExtend_FalseOutsideWindow() public view {
        assertFalse(AuctionMath.shouldExtend(uint64(block.timestamp), uint64(block.timestamp + 100), 10, 0, 3));
    }
    function testFuzz_shouldExtend_NeverExtendsPastMax(uint64 nowTs, uint64 endTime, uint64 window, uint8 used, uint8 max)
        public
        pure
    {
        vm.assume(used >= max);
        assertFalse(AuctionMath.shouldExtend(nowTs, endTime, window, used, max));
    }
}

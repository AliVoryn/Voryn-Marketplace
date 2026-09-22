pragma solidity ^0.8.24;
import "forge-std/Test.sol";
import "../../src/libraries/RewardMath.sol";
contract RewardMathTest is Test {
    uint256 internal constant SCALE = 1e18;
    function test_userAccrued_ZeroWhenIndexHasNotMoved() public pure {
        assertEq(RewardMath.userAccrued(100 ether, 5 * SCALE, 5 * SCALE), 0);
    }
    function test_userAccrued_ZeroWhenGlobalIndexBehindUserIndex() public pure {
        assertEq(RewardMath.userAccrued(100 ether, 1 * SCALE, 5 * SCALE), 0);
    }
    function test_userAccrued_NormalCase() public pure {
        uint256 accrued = RewardMath.userAccrued(100 ether, 3 * SCALE, 1 * SCALE);
        assertEq(accrued, 200 ether);
    }
    function test_rewardPerToken_UnchangedWhenNoStake() public pure {
        assertEq(RewardMath.rewardPerToken(7 * SCALE, 1 ether, 100, 0), 7 * SCALE);
    }
    function test_rewardPerToken_UnchangedWhenNoElapsedTime() public pure {
        assertEq(RewardMath.rewardPerToken(7 * SCALE, 1 ether, 0, 1000 ether), 7 * SCALE);
    }
    function test_rewardPerToken_Increments() public pure {
        uint256 result = RewardMath.rewardPerToken(0, 1 ether, 10, 100 ether);
        assertEq(result, SCALE / 10);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import { RewardMath } from "../../src/libraries/RewardMath.sol";

contract SymbolicRewardMathHarness {
    function accruedIsZeroWhenIndexDoesNotAdvance(uint256 amount, uint256 index, uint256 userIndex)
        external
        pure
        returns (bool)
    {
        if (index > userIndex) return true;
        assert(RewardMath.userAccrued(amount, index, userIndex) == 0);
        return true;
    }

    function rewardIndexDoesNotDecrease(uint256 currentIndex, uint256 rewardRate, uint256 elapsed, uint256 totalStaked)
        external
        pure
        returns (bool)
    {
        if (totalStaked == 0 || rewardRate == 0 || elapsed == 0) return true;
        uint256 nextIndex = RewardMath.rewardPerToken(currentIndex, rewardRate, elapsed, totalStaked);
        assert(nextIndex >= currentIndex);
        return true;
    }
}

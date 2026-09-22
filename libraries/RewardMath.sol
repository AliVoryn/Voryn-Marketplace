// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

library RewardMath {
    uint internal constant SCALE = 1e18;

    function accumulated(uint principal,uint rewardPerSecond,uint elapsed) internal pure returns (uint) {
        return principal * rewardPerSecond * elapsed / SCALE;
    }

    function rewardPerShare(uint rewardAmount,uint totalStaked) internal pure returns (uint) {
        if (totalStaked == 0) return 0;
        return rewardAmount * SCALE / totalStaked;
    }

    function userReward(uint amount,uint globalIndex,uint userIndex) internal pure returns (uint) {
        if (globalIndex <= userIndex) return 0;
        return amount * (globalIndex - userIndex) / SCALE;
    }

    function userAccrued(uint amount,uint globalIndex,uint userIndex) internal pure returns (uint) {
        return userReward(amount, globalIndex, userIndex);
    }
    function rewardPerToken(uint currentIndex,uint rewardRate,uint elapsed,uint totalStaked) internal pure returns (uint) {
        if (totalStaked == 0 ||rewardRate == 0 ||elapsed == 0) return currentIndex;
    

        uint reward = rewardRate * elapsed;

        uint rewardPerTokenIncrement =
            reward * SCALE / totalStaked;

        return currentIndex + rewardPerTokenIncrement;
    }
}

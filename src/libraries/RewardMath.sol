// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

library RewardMath {
    uint256 internal constant SCALE = 1e18;

    function userAccrued(uint256 amount, uint256 globalIndex, uint256 userIndex) internal pure returns (uint256) {
        if (globalIndex <= userIndex) return 0;
        return amount * (globalIndex - userIndex) / SCALE;
    }

    function rewardPerToken(uint256 currentIndex, uint256 rewardRate, uint256 elapsed, uint256 totalStaked)
        internal
        pure
        returns (uint256)
    {
        if (totalStaked == 0 || rewardRate == 0 || elapsed == 0) return currentIndex;
        uint256 reward = rewardRate * elapsed;
        uint256 rewardPerTokenIncrement = reward * SCALE / totalStaked;
        return currentIndex + rewardPerTokenIncrement;
    }
}

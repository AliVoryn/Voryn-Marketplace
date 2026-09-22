pragma solidity ^0.8.24;
library RewardMath {
    uint internal constant SCALE = 1e18;
    function userAccrued(uint amount, uint globalIndex, uint userIndex) internal pure returns (uint) {
        if (globalIndex <= userIndex) return 0;
        return amount * (globalIndex - userIndex) / SCALE;
    }
    function rewardPerToken(uint currentIndex, uint rewardRate, uint elapsed, uint totalStaked) internal pure returns (uint) {
        if (totalStaked == 0 || rewardRate == 0 || elapsed == 0) return currentIndex;
        uint reward = rewardRate * elapsed;
        uint rewardPerTokenIncrement = reward * SCALE / totalStaked;
        return currentIndex + rewardPerTokenIncrement;
    }
}

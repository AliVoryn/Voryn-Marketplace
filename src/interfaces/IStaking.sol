// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IStaking {
    enum RewardPhase {
        Inactive,
        Scheduled,
        Active,
        Ended
    }

    struct Position {
        uint256 amount;
        uint256 rewardDebt;
        uint64 lastAction;
        bool active;
    }
    event Staked(address indexed account, uint256 amount);
    event Unstaked(address indexed account, uint256 amount);
    event RewardClaimed(address indexed account, uint256 amount);
    event RewardCompounded(address indexed account, uint256 amount);
    event EmergencyUnstake(address indexed account, uint256 principal, uint256 penalty);
    event RewardProgramScheduled(uint64 startAt, uint64 endAt, uint256 rewardAmount, uint256 rewardRate);
    event RewardProgramFunded(uint256 amount, address indexed source);
    event CooldownUpdated(uint64 oldCooldown, uint64 newCooldown);
    event BoundsUpdated(uint256 minimumStake, uint256 maximumStake);
    event EmergencyPenaltyUpdated(uint16 penaltyBps);
    error ZeroAmount();
    error AmountTooLarge();
    error NoPosition();
    error InsufficientStake();
    error RewardTransferFailed();
    error InvalidRewardProgram();
    error RewardProgramNotActive();
    error CooldownActive();
    error InvalidCooldown();
    error InvalidPenalty();
    error InsufficientRewardInventory();
    error InvalidStartTime();
    error ZeroAddress();
    function stake() external payable;
    function unstake(uint256 amount) external;
    function claimReward() external;
    function compoundReward() external;
    function emergencyUnstake() external;
    function fundRewards() external payable;
    function fundRewardsFromTreasury(uint256 amount) external;
    function scheduleRewardProgram(uint64 startAt, uint64 endAt, uint256 rewardAmount) external payable;
    function pendingReward(address account) external view returns (uint256);
    function getPosition(address account) external view returns (Position memory);
    function currentRewardPhase() external view returns (RewardPhase);
    function rewardRate() external view returns (uint256);
    function rewardPerTokenStored() external view returns (uint256);
    function rewardInventory() external view returns (uint256);
}

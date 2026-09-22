pragma solidity ^0.8.24;
interface IStaking {
    enum RewardPhase { Inactive, Scheduled, Active, Ended }
    struct Position {
        uint amount;
        uint rewardDebt;
        uint64 lastAction;
        bool active;
    }
    event Staked(address indexed account, uint amount);
    event Unstaked(address indexed account, uint amount);
    event RewardClaimed(address indexed account, uint amount);
    event RewardCompounded(address indexed account, uint amount);
    event EmergencyUnstake(address indexed account, uint principal, uint penalty);
    event RewardProgramScheduled(uint64 startAt, uint64 endAt, uint rewardAmount, uint rewardRate);
    event RewardProgramFunded(uint amount, address indexed source);
    event CooldownUpdated(uint64 oldCooldown, uint64 newCooldown);
    event BoundsUpdated(uint minimumStake, uint maximumStake);
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
    function unstake(uint amount) external;
    function claimReward() external;
    function compoundReward() external;
    function emergencyUnstake() external;
    function fundRewards() external payable;
    function fundRewardsFromTreasury(uint amount) external;
    function scheduleRewardProgram(uint64 startAt, uint64 endAt, uint rewardAmount) external payable;
    function pendingReward(address account) external view returns (uint);
    function getPosition(address account) external view returns (Position memory);
    function currentRewardPhase() external view returns (RewardPhase);
    function rewardRate() external view returns (uint);
    function rewardPerTokenStored() external view returns (uint);
    function rewardInventory() external view returns (uint);
}

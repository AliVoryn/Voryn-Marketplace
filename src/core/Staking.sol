// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import "@openzeppelin/contracts/access/Ownable2Step.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { IStaking } from "../interfaces/IStaking.sol";
import { ITreasury } from "../interfaces/ITreasury.sol";
import { RewardMath } from "../libraries/RewardMath.sol";

contract Staking is Ownable2Step, Pausable, ReentrancyGuard, IStaking {
    uint256 public constant ACC_SCALE = 1e18;
    uint256 public constant MAX_REWARD_RATE = 1e24;

    struct UserAccounting {
        uint256 amount;
        uint256 rewards;
        uint256 rewardPerTokenPaid;
        uint64 cooldownEndsAt;
        bool active;
    }
    mapping(address => Position) private positions;
    mapping(address => UserAccounting) private accounting;
    uint256 public totalStaked;
    uint256 public totalRewardLiability;
    uint256 public rewardReserve;
    uint256 public override rewardRate;
    uint256 public override rewardPerTokenStored;
    uint64 public rewardStartAt;
    uint64 public periodFinish;
    uint64 public lastUpdateTime;
    uint256 public minimumStake;
    uint256 public maximumStake;
    uint64 public unstakeCooldown = 1 days;
    uint16 public emergencyPenaltyBps = 1000;
    address public immutable treasury;

    constructor(address initialOwner, address treasury_) Ownable(initialOwner) {
        if (treasury_ == address(0) || treasury_.code.length == 0) revert ZeroAddress();
        treasury = treasury_;
        minimumStake = 0.01 ether;
    }

    function fundRewards() external payable override {
        if (msg.value == 0) revert ZeroAmount();
        rewardReserve += msg.value;
        emit RewardProgramFunded(msg.value, msg.sender);
    }

    function fundRewardsFromTreasury(uint256 amount) external override onlyOwner {
        if (amount == 0) revert ZeroAmount();
        ITreasury(treasury).pay(payable(address(this)), amount, keccak256("STAKING_REWARD_FUNDING"));
        rewardReserve += amount;
        emit RewardProgramFunded(amount, treasury);
    }

    function scheduleRewardProgram(uint64 startAt, uint64 endAt, uint256 rewardAmount)
        external
        payable
        override
        onlyOwner
    {
        _updateGlobal();
        if (msg.value > 0) {
            rewardReserve += msg.value;
            emit RewardProgramFunded(msg.value, msg.sender);
        }
        RewardPhase phase = currentRewardPhase();
        if (phase == RewardPhase.Active || phase == RewardPhase.Scheduled) revert InvalidRewardProgram();
        if (startAt == 0 || startAt < block.timestamp || startAt >= endAt) revert InvalidStartTime();
        uint256 duration = endAt - startAt;
        uint256 fundedBalance = rewardInventory() + rewardReserve;
        if (rewardAmount == 0 || rewardAmount > fundedBalance) revert InvalidRewardProgram();
        if (rewardAmount % duration != 0) revert InvalidRewardProgram();
        uint256 newRate = rewardAmount / duration;
        if (newRate == 0 || newRate > MAX_REWARD_RATE) revert InvalidRewardProgram();
        uint256 effectiveReward = newRate * duration;
        uint256 reserveTopUp = effectiveReward > rewardReserve ? effectiveReward - rewardReserve : 0;
        if (reserveTopUp > rewardInventory()) revert InvalidRewardProgram();
        rewardReserve += reserveTopUp;
        rewardStartAt = startAt;
        periodFinish = endAt;
        rewardRate = newRate;
        lastUpdateTime = startAt;
        emit RewardProgramScheduled(startAt, endAt, effectiveReward, newRate);
    }

    function stake() external payable override nonReentrant whenNotPaused {
        if (msg.value == 0) revert ZeroAmount();
        _updateAccount(msg.sender);
        UserAccounting storage user = accounting[msg.sender];
        uint256 newAmount = user.amount + msg.value;
        if (newAmount < minimumStake) revert ZeroAmount();
        if (maximumStake != 0 && newAmount > maximumStake) revert AmountTooLarge();
        user.amount = newAmount;
        user.active = true;
        user.cooldownEndsAt = _cooldownEndsAt();
        positions[msg.sender].amount = newAmount;
        positions[msg.sender].active = true;
        positions[msg.sender].lastAction = uint64(block.timestamp);
        totalStaked += msg.value;
        emit Staked(msg.sender, msg.value);
    }

    function unstake(uint256 amount) external override nonReentrant whenNotPaused {
        if (amount == 0) revert ZeroAmount();
        _updateAccount(msg.sender);
        UserAccounting storage user = accounting[msg.sender];
        if (!user.active) revert NoPosition();
        if (block.timestamp < user.cooldownEndsAt) revert CooldownActive();
        if (amount > user.amount) revert InsufficientStake();
        user.amount -= amount;
        totalStaked -= amount;
        positions[msg.sender].amount = user.amount;
        positions[msg.sender].lastAction = uint64(block.timestamp);
        if (user.amount == 0) {
            user.active = false;
            positions[msg.sender].active = false;
        }
        (bool success,) = payable(msg.sender).call{ value: amount }("");
        if (!success) revert RewardTransferFailed();
        emit Unstaked(msg.sender, amount);
    }

    function currentRewardPhase() public view override returns (RewardPhase) {
        if (rewardStartAt == 0) return RewardPhase.Inactive;
        if (block.timestamp < rewardStartAt) return RewardPhase.Scheduled;
        if (block.timestamp >= periodFinish) return RewardPhase.Ended;
        return RewardPhase.Active;
    }

    function claimReward() external override nonReentrant {
        _updateAccount(msg.sender);
        uint256 reward = accounting[msg.sender].rewards;
        if (reward == 0) return;
        if (reward > _claimableRewardBalance()) revert InsufficientRewardInventory();
        accounting[msg.sender].rewards = 0;
        totalRewardLiability -= reward;
        positions[msg.sender].rewardDebt = 0;
        (bool success,) = payable(msg.sender).call{ value: reward }("");
        if (!success) revert RewardTransferFailed();
        emit RewardClaimed(msg.sender, reward);
    }

    function rewardInventory() public view override returns (uint256) {
        uint256 reserved = totalStaked + totalRewardLiability + rewardReserve;
        if (address(this).balance <= reserved) return 0;
        return address(this).balance - reserved;
    }

    function compoundReward() external override nonReentrant whenNotPaused {
        _updateAccount(msg.sender);
        UserAccounting storage user = accounting[msg.sender];
        uint256 reward = user.rewards;
        if (reward == 0) return;
        if (reward > _claimableRewardBalance()) revert InsufficientRewardInventory();
        uint256 newAmount = user.amount + reward;
        if (maximumStake != 0 && newAmount > maximumStake) revert AmountTooLarge();
        user.rewards = 0;
        totalRewardLiability -= reward;
        user.amount = newAmount;
        user.rewardPerTokenPaid = rewardPerTokenStored;
        user.cooldownEndsAt = _cooldownEndsAt();
        user.active = true;
        totalStaked += reward;
        positions[msg.sender].amount = newAmount;
        positions[msg.sender].rewardDebt = 0;
        positions[msg.sender].active = true;
        positions[msg.sender].lastAction = uint64(block.timestamp);
        emit RewardCompounded(msg.sender, reward);
    }

    function emergencyUnstake() external override nonReentrant {
        _updateAccount(msg.sender);
        UserAccounting storage user = accounting[msg.sender];
        if (!user.active) revert NoPosition();
        uint256 principal = user.amount;
        uint256 penalty = principal * emergencyPenaltyBps / 10_000;
        uint256 payout = principal - penalty;
        totalRewardLiability -= user.rewards;
        user.amount = 0;
        user.rewards = 0;
        user.rewardPerTokenPaid = rewardPerTokenStored;
        user.active = false;
        positions[msg.sender].amount = 0;
        positions[msg.sender].rewardDebt = 0;
        positions[msg.sender].active = false;
        positions[msg.sender].lastAction = uint64(block.timestamp);
        totalStaked -= principal;
        (bool success,) = payable(msg.sender).call{ value: payout }("");
        if (!success) revert RewardTransferFailed();
        emit EmergencyUnstake(msg.sender, principal, penalty);
    }

    function configureBounds(uint256 minimum, uint256 maximum) external onlyOwner {
        if (maximum != 0 && maximum < minimum) revert AmountTooLarge();
        minimumStake = minimum;
        maximumStake = maximum;
        emit BoundsUpdated(minimum, maximum);
    }

    function setCooldown(uint64 cooldown) external onlyOwner {
        if (cooldown > 30 days) revert InvalidCooldown();
        uint64 old = unstakeCooldown;
        unstakeCooldown = cooldown;
        emit CooldownUpdated(old, cooldown);
    }

    function setEmergencyPenalty(uint16 bps) external onlyOwner {
        if (bps > 5000) revert InvalidPenalty();
        emergencyPenaltyBps = bps;
        emit EmergencyPenaltyUpdated(bps);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function pendingReward(address account) public view override returns (uint256) {
        UserAccounting memory user = accounting[account];
        return user.rewards + RewardMath.userAccrued(user.amount, _currentRewardPerToken(), user.rewardPerTokenPaid);
    }

    function getPosition(address account) external view override returns (Position memory) {
        Position memory p = positions[account];
        p.rewardDebt = accounting[account].rewards;
        return p;
    }

    function _updateGlobal() internal {
        uint256 newIndex = _currentRewardPerToken();
        uint256 emitted = _emittedSinceLastUpdate();
        if (emitted > 0) {
            if (emitted > rewardReserve) revert InsufficientRewardInventory();
            rewardReserve -= emitted;
            totalRewardLiability += emitted;
        }
        rewardPerTokenStored = newIndex;
        if (block.timestamp < rewardStartAt) lastUpdateTime = rewardStartAt;
        else if (block.timestamp >= periodFinish) lastUpdateTime = periodFinish;
        else lastUpdateTime = uint64(block.timestamp);
    }

    function _updateAccount(address account) internal {
        _updateGlobal();
        UserAccounting storage user = accounting[account];
        uint256 newlyAccrued = RewardMath.userAccrued(user.amount, rewardPerTokenStored, user.rewardPerTokenPaid);
        user.rewards += newlyAccrued;
        user.rewardPerTokenPaid = rewardPerTokenStored;
        positions[account].rewardDebt = user.rewards;
        positions[account].lastAction = uint64(block.timestamp);
    }

    function _emittedSinceLastUpdate() internal view returns (uint256) {
        if (rewardRate == 0 || totalStaked == 0 || rewardStartAt == 0) {
            return 0;
        }
        uint256 from = lastUpdateTime < rewardStartAt ? rewardStartAt : lastUpdateTime;
        uint256 to = block.timestamp > periodFinish ? periodFinish : block.timestamp;
        if (to <= from) return 0;
        return (to - from) * rewardRate;
    }

    function _currentRewardPerToken() internal view returns (uint256) {
        if (totalStaked == 0 || rewardRate == 0) return rewardPerTokenStored;
        uint256 from = lastUpdateTime < rewardStartAt ? rewardStartAt : lastUpdateTime;
        uint256 to = block.timestamp > periodFinish ? periodFinish : block.timestamp;
        if (to <= from) return rewardPerTokenStored;
        return RewardMath.rewardPerToken(rewardPerTokenStored, rewardRate, to - from, totalStaked);
    }

    function _claimableRewardBalance() internal view returns (uint256) {
        uint256 reserved = totalStaked + rewardReserve;
        if (address(this).balance <= reserved) return 0;
        return address(this).balance - reserved;
    }

    function _cooldownEndsAt() internal view returns (uint64) {
        if (uint256(block.timestamp) > type(uint64).max - unstakeCooldown) revert InvalidCooldown();
        return uint64(block.timestamp + unstakeCooldown);
    }
    receive() external payable { }
}

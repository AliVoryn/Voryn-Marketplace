pragma solidity ^0.8.24;
import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "../interfaces/IStaking.sol";
import "../interfaces/ITreasury.sol";
import "../libraries/RewardMath.sol";
contract Staking is Ownable2Step, Pausable, ReentrancyGuard, IStaking {
    using Address for address payable;
    uint public constant ACC_SCALE = 1e18;
    uint public constant MAX_REWARD_RATE = 1e24;
    struct UserAccounting {
        uint amount;
        uint rewards;
        uint rewardPerTokenPaid;
        uint64 cooldownEndsAt;
        bool active;
    }
    mapping(address => Position) private positions;
    mapping(address => UserAccounting) private accounting;
    uint public totalStaked;
    uint public totalRewardLiability;
    uint public rewardReserve;
    uint public override rewardRate;
    uint public override rewardPerTokenStored;
    uint64 public rewardStartAt;
    uint64 public periodFinish;
    uint64 public lastUpdateTime;
    uint public minimumStake;
    uint public maximumStake;
    uint64 public unstakeCooldown = 1 days;
    uint16 public emergencyPenaltyBps = 1000;
    address public immutable treasury;
    constructor(address initialOwner, address treasury_) Ownable(initialOwner) {
        if (treasury_ == address(0)) revert ZeroAddress();
        treasury = treasury_;
        minimumStake = 0.01 ether;
    }
    function fundRewards() external payable override {
        if (msg.value == 0) revert ZeroAmount();
        rewardReserve += msg.value;
        emit RewardProgramFunded(msg.value, msg.sender);
    }
    function fundRewardsFromTreasury(uint amount) external override onlyOwner {
        if (amount == 0) revert ZeroAmount();
        ITreasury(treasury).pay(
            payable(address(this)),
            amount,
            keccak256("STAKING_REWARD_FUNDING")
        );
        rewardReserve += amount;
        emit RewardProgramFunded(amount, treasury);
    }
    function scheduleRewardProgram(uint64 startAt,uint64 endAt,uint rewardAmount)  external  payable   override   onlyOwner {
        _updateGlobal();
        if (msg.value > 0) {
            rewardReserve += msg.value;
            emit RewardProgramFunded(msg.value, msg.sender);
        }
        RewardPhase phase = currentRewardPhase();
        if (phase == RewardPhase.Active ||phase == RewardPhase.Scheduled) 
            revert InvalidRewardProgram();
        if (startAt >= endAt) revert InvalidRewardProgram();
        uint duration = endAt - startAt ;
        if (duration == 0) revert InvalidRewardProgram();
        uint fundedBalance = rewardInventory() + rewardReserve;
        if (rewardAmount > fundedBalance) revert InvalidRewardProgram();
        uint newRate = rewardAmount / duration;
        if (newRate == 0 || newRate > MAX_REWARD_RATE) revert InvalidRewardProgram();
        uint effectiveReward = newRate * duration;
        if (effectiveReward > rewardAmount) effectiveReward = rewardAmount;
        rewardStartAt = startAt;
        periodFinish = endAt;
        rewardRate = newRate;
        rewardReserve = rewardInventory() + rewardReserve;
        lastUpdateTime = startAt;
        emit RewardProgramScheduled(startAt, endAt, effectiveReward, newRate);
    }
    function stake () external payable override nonReentrant whenNotPaused {
        if(msg.value == 0 ) revert ZeroAmount();
        _updateAccount(msg.sender);
        UserAccounting storage user = accounting[msg.sender] ;
        uint newAmount = user.amount + msg.value ;
        if (newAmount < minimumStake) revert ZeroAmount();
        if (maximumStake != 0 && newAmount > maximumStake) revert AmountTooLarge();
        user.amount = newAmount ;
        user.active = true ;
        user.cooldownEndsAt = uint64(block.timestamp + unstakeCooldown) ;
        positions[msg.sender].amount = newAmount;
        positions[msg.sender].active = true;
        positions[msg.sender].lastAction = uint64(block.timestamp);
        totalStaked += msg.value;
        emit Staked(msg.sender, msg.value);
    }
    function unstake (uint amount) external override nonReentrant whenNotPaused {
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
        (bool success,) = payable(msg.sender).call{value: amount}("");
        if (!success) revert RewardTransferFailed();
        emit Unstaked(msg.sender, amount);
    }
    function currentRewardPhase() public view override returns (RewardPhase) {
        if (rewardStartAt == 0) return RewardPhase.Inactive;
        if (block.timestamp < rewardStartAt) return RewardPhase.Scheduled;
        if (block.timestamp >= periodFinish) return RewardPhase.Ended;
        return RewardPhase.Active;
    }
    function claimReward () external override nonReentrant {
        _updateAccount(msg.sender);
        uint reward = accounting[msg.sender].rewards;
        if (reward == 0) return ;
        if (reward > _claimableRewardBalance()) revert InsufficientRewardInventory() ;
        accounting[msg.sender].rewards = 0;
        totalRewardLiability -= reward;
        positions[msg.sender].rewardDebt = 0;
        (bool success,) = payable(msg.sender).call{value: reward}("");
        if (!success) revert RewardTransferFailed();
        emit RewardClaimed(msg.sender, reward);
    }
    function rewardInventory() public view override returns (uint) {
        uint reserved = totalStaked + totalRewardLiability + rewardReserve;
        if (address(this).balance <= reserved) return 0;
        return address(this).balance - reserved;
    }
    function compoundReward() external override nonReentrant whenNotPaused {
        _updateAccount(msg.sender);
        UserAccounting storage user = accounting[msg.sender];
        uint reward = user.rewards;
        if (reward == 0) return;
        if (reward > _claimableRewardBalance()) revert InsufficientRewardInventory();
        uint newAmount = user.amount + reward;
        if (maximumStake != 0 && newAmount > maximumStake) revert AmountTooLarge();
        user.rewards = 0;
        totalRewardLiability -= reward;
        user.amount = newAmount;
        user.rewardPerTokenPaid = rewardPerTokenStored;
        user.cooldownEndsAt = uint64(block.timestamp + unstakeCooldown);
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
        uint principal = user.amount;
        uint penalty = principal * emergencyPenaltyBps / 10_000;
        uint payout = principal - penalty;
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
        (bool success,) = payable(msg.sender).call{value: payout}("");
        if (!success) revert RewardTransferFailed();
        emit EmergencyUnstake(msg.sender, principal, penalty);
    }
    function configureBounds(uint minimum, uint maximum) external onlyOwner {
        if (maximum != 0 && maximum < minimum) revert AmountTooLarge();
        minimumStake = minimum;
        maximumStake = maximum;
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
    function pause() external onlyOwner { _pause(); }
    function unpause() external onlyOwner { _unpause(); }
    function pendingReward(address account) public view override returns (uint) {
        UserAccounting memory user = accounting[account];
        return user.rewards + RewardMath.userAccrued(
            user.amount,
            _currentRewardPerToken(),
            user.rewardPerTokenPaid
        );
    }
       function getPosition(address account) external view override returns (Position memory) {
        Position memory p = positions[account];
        p.rewardDebt = accounting[account].rewards;
        return p;
    }
    function _updateGlobal() internal {
        uint newIndex =  _currentRewardPerToken();
        uint emitted = _emittedSinceLastUpdate();
        if (emitted > 0) {
            if (emitted > rewardReserve) emitted = rewardReserve;
            rewardReserve -= emitted;
            totalRewardLiability += emitted;
        }
        rewardPerTokenStored = newIndex;
        if (block.timestamp < rewardStartAt) lastUpdateTime = rewardStartAt;
        else if (block.timestamp >= periodFinish) lastUpdateTime = periodFinish;
        else lastUpdateTime = uint64(block.timestamp);
    }
    function _updateAccount (address account ) internal {
        _updateGlobal();
        UserAccounting storage user = accounting[account];
        uint newlyAccrued = RewardMath.userAccrued(user.amount,rewardPerTokenStored,user.rewardPerTokenPaid);
        user.rewards += newlyAccrued;
        user.rewardPerTokenPaid = rewardPerTokenStored;
        positions[account].rewardDebt = user.rewards;
        positions[account].lastAction = uint64(block.timestamp);
    } 
    function _emittedSinceLastUpdate () internal view returns (uint) {
        if ( rewardRate == 0 || totalStaked == 0 || rewardStartAt == 0) 
            return 0;
        uint from = lastUpdateTime < rewardStartAt ? rewardStartAt : lastUpdateTime;
        uint to = block.timestamp > periodFinish ? periodFinish : block.timestamp;
        if (to <= from) return 0;
        return (to - from) * rewardRate;
    }
    function _currentRewardPerToken() internal view returns (uint) {
        if ( totalStaked == 0 || rewardRate == 0) return rewardPerTokenStored;
        uint from = lastUpdateTime < rewardStartAt ? rewardStartAt : lastUpdateTime  ;
        uint to = block.timestamp > periodFinish ? periodFinish : block.timestamp;
        if (to <= from) return rewardPerTokenStored;
        return RewardMath.rewardPerToken(rewardPerTokenStored,rewardRate,to - from,totalStaked);
    }
    function _claimableRewardBalance() internal view returns (uint) {
        uint reserved = totalStaked + rewardReserve;
        if (address(this).balance <= reserved) return 0;
        return address(this).balance - reserved;
    }
    receive() external payable {}
}

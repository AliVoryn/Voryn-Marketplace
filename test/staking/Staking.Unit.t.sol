// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import "../support/TestBase.sol";

contract RejectingStaker {
    Staking internal immutable staking;

    constructor(Staking staking_) {
        staking = staking_;
    }

    receive() external payable {
        revert();
    }

    function stake() external payable {
        staking.stake{ value: msg.value }();
    }

    function unstake(uint256 amount) external {
        staking.unstake(amount);
    }

    function emergencyUnstake() external {
        staking.emergencyUnstake();
    }
}

contract StakingRewardsTest is ProtocolTestBase {
    Staking internal staking;

    function setUp() public {
        _setUpCore();
        staking = _deployStaking(address(treasury));
        vm.prank(admin);
        treasury.setAuthorizedPayer(address(staking), true);
    }

    function test_Stake_BelowMinimumReverts() public {
        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        vm.expectRevert(IStaking.ZeroAmount.selector);
        staking.stake{ value: 0.001 ether }();
    }

    function test_Stake_RejectsZeroAndMaximumBoundary() public {
        vm.prank(buyer);
        vm.expectRevert(IStaking.ZeroAmount.selector);
        staking.stake();
        vm.prank(admin);
        staking.configureBounds(1 ether, 2 ether);
        vm.deal(buyer, 3 ether);
        vm.prank(buyer);
        staking.stake{ value: 2 ether }();
        vm.prank(buyer);
        vm.expectRevert(IStaking.AmountTooLarge.selector);
        staking.stake{ value: 1 wei }();
    }

    function test_StakeAndUnstakeRejectMissingOrExcessPosition() public {
        vm.prank(buyer);
        vm.expectRevert(IStaking.NoPosition.selector);
        staking.unstake(1 ether);
        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        staking.stake{ value: 1 ether }();
        vm.warp(block.timestamp + 1 days + 1);
        vm.prank(buyer);
        vm.expectRevert(IStaking.InsufficientStake.selector);
        staking.unstake(1 ether + 1 wei);
    }

    function test_Stake_RecordsPositionAndTotal() public {
        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        staking.stake{ value: 1 ether }();
        assertEq(staking.totalStaked(), 1 ether);
        assertEq(staking.getPosition(buyer).amount, 1 ether);
    }

    function test_Unstake_RevertsDuringCooldown() public {
        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        staking.stake{ value: 1 ether }();
        vm.prank(buyer);
        vm.expectRevert(IStaking.CooldownActive.selector);
        staking.unstake(1 ether);
    }

    function test_Unstake_SucceedsAfterCooldown() public {
        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        staking.stake{ value: 1 ether }();
        vm.warp(block.timestamp + 1 days + 1);
        uint256 before = buyer.balance;
        vm.prank(buyer);
        staking.unstake(1 ether);
        assertEq(buyer.balance, before + 1 ether);
    }

    function test_Unstake_PartialLeavesPositionActive() public {
        vm.deal(buyer, 2 ether);
        vm.prank(buyer);
        staking.stake{ value: 2 ether }();
        vm.warp(block.timestamp + 1 days + 1);
        vm.prank(buyer);
        staking.unstake(1 ether);
        assertEq(staking.getPosition(buyer).amount, 1 ether);
        assertTrue(staking.getPosition(buyer).active);
    }

    function _fundAndSchedule(uint256 rewardAmount, uint64 duration) internal {
        vm.deal(admin, rewardAmount);
        vm.startPrank(admin);
        staking.scheduleRewardProgram{ value: rewardAmount }(
            uint64(block.timestamp), uint64(block.timestamp) + duration, rewardAmount
        );
        vm.stopPrank();
    }

    function test_RewardAccrual_LinearOverTime() public {
        vm.deal(buyer, 100 ether);
        vm.prank(buyer);
        staking.stake{ value: 100 ether }();
        _fundAndSchedule(100 ether, 100);
        vm.warp(block.timestamp + 50);
        uint256 pending = staking.pendingReward(buyer);
        assertApproxEqAbs(pending, 50 ether, 1e12, "sole staker should accrue ~all emitted rewards");
    }

    function test_ClaimReward_PaysAndZeroes() public {
        vm.deal(buyer, 100 ether);
        vm.prank(buyer);
        staking.stake{ value: 100 ether }();
        _fundAndSchedule(100 ether, 100);
        vm.warp(block.timestamp + 100);
        uint256 before = buyer.balance;
        vm.prank(buyer);
        staking.claimReward();
        assertGt(buyer.balance, before);
        assertEq(staking.pendingReward(buyer), 0);
    }

    function test_CompoundReward_IncreasesStakeNotBalance() public {
        vm.deal(buyer, 100 ether);
        vm.prank(buyer);
        staking.stake{ value: 100 ether }();
        _fundAndSchedule(100 ether, 100);
        vm.warp(block.timestamp + 100);
        uint256 stakeBefore = staking.getPosition(buyer).amount;
        uint256 balBefore = buyer.balance;
        vm.prank(buyer);
        staking.compoundReward();
        assertGt(staking.getPosition(buyer).amount, stakeBefore);
        assertEq(buyer.balance, balBefore, "compounding must not pay out ETH");
    }

    function test_EmergencyUnstake_AppliesPenaltyAndForfeitsRewards() public {
        vm.deal(buyer, 100 ether);
        vm.prank(buyer);
        staking.stake{ value: 100 ether }();
        _fundAndSchedule(100 ether, 100);
        vm.warp(block.timestamp + 50);
        assertGt(staking.pendingReward(buyer), 0);
        uint256 before = buyer.balance;
        vm.prank(buyer);
        staking.emergencyUnstake();
        assertEq(buyer.balance, before + 90 ether);
        assertEq(staking.pendingReward(buyer), 0, "rewards are forfeited on emergency unstake");
    }

    function test_EmergencyUnstake_RejectsMissingPosition() public {
        vm.prank(buyer);
        vm.expectRevert(IStaking.NoPosition.selector);
        staking.emergencyUnstake();
    }

    function test_ClaimAndCompoundWithoutRewardDoNotChangeState() public {
        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        staking.stake{ value: 1 ether }();
        uint256 before = staking.getPosition(buyer).amount;
        vm.prank(buyer);
        staking.claimReward();
        vm.prank(buyer);
        staking.compoundReward();
        assertEq(staking.getPosition(buyer).amount, before);
    }

    function test_ScheduleRewardProgram_RevertsWhileActive() public {
        _fundAndSchedule(100 ether, 100);
        vm.deal(admin, 1 ether);
        vm.prank(admin);
        vm.expectRevert(IStaking.InvalidRewardProgram.selector);
        staking.scheduleRewardProgram{ value: 1 ether }(uint64(block.timestamp), uint64(block.timestamp) + 10, 1 ether);
    }

    function test_ScheduleRewardProgram_RejectsInvalidRangeFundingAndRate() public {
        vm.deal(admin, 10 ether);
        uint64 startAt = uint64(block.timestamp + 10);
        vm.startPrank(admin);
        vm.expectRevert(IStaking.InvalidStartTime.selector);
        staking.scheduleRewardProgram(startAt, startAt, 1 ether);
        vm.expectRevert(IStaking.InvalidStartTime.selector);
        staking.scheduleRewardProgram(startAt + 1, startAt, 1 ether);
        vm.expectRevert(IStaking.InvalidRewardProgram.selector);
        staking.scheduleRewardProgram(startAt, startAt + 10, 0);
        vm.expectRevert(IStaking.InvalidRewardProgram.selector);
        staking.scheduleRewardProgram(startAt, startAt + 10, 1 ether);
        vm.stopPrank();
    }

    function test_ScheduleRewardProgram_RejectsNonDivisibleRewardAmount() public {
        uint64 startAt = uint64(block.timestamp + 10);
        vm.deal(admin, 10 ether);
        vm.prank(admin);
        vm.expectRevert(IStaking.InvalidRewardProgram.selector);
        staking.scheduleRewardProgram{ value: 10 ether }(startAt, startAt + 6, 10 ether - 1);
    }

    function test_FundingAndConfigurationBoundaries() public {
        vm.prank(buyer);
        vm.expectRevert(IStaking.ZeroAmount.selector);
        staking.fundRewards();
        vm.prank(admin);
        vm.expectRevert(IStaking.AmountTooLarge.selector);
        staking.configureBounds(2 ether, 1 ether);
        vm.prank(admin);
        vm.expectRevert(IStaking.InvalidCooldown.selector);
        staking.setCooldown(30 days + 1);
        vm.prank(admin);
        vm.expectRevert(IStaking.InvalidPenalty.selector);
        staking.setEmergencyPenalty(5001);
        vm.prank(admin);
        staking.configureBounds(0.01 ether, 0);
        vm.prank(admin);
        staking.setCooldown(0);
        vm.prank(admin);
        staking.setEmergencyPenalty(0);
        assertEq(staking.unstakeCooldown(), 0);
        assertEq(staking.emergencyPenaltyBps(), 0);
    }

    function test_PauseBlocksStakeAndUnpauseRestoresIt() public {
        vm.prank(admin);
        staking.pause();
        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        vm.expectRevert();
        staking.stake{ value: 1 ether }();
        vm.prank(admin);
        staking.unpause();
        vm.prank(buyer);
        staking.stake{ value: 1 ether }();
        assertEq(staking.totalStaked(), 1 ether);
    }

    function test_RewardPhaseBoundariesAndViews() public {
        assertEq(uint8(staking.currentRewardPhase()), uint8(IStaking.RewardPhase.Inactive));
        _fundAndSchedule(10 ether, 100);
        assertEq(uint8(staking.currentRewardPhase()), uint8(IStaking.RewardPhase.Active));
        vm.warp(block.timestamp + 100);
        assertEq(uint8(staking.currentRewardPhase()), uint8(IStaking.RewardPhase.Ended));
        assertEq(staking.rewardReserve(), 10 ether);
        assertEq(staking.rewardInventory(), 0);
    }

    function test_FundRewardsFromTreasury_RequiresAvailableTreasuryFunds() public {
        vm.prank(admin);
        vm.expectRevert(ITreasury.InsufficientAvailableBalance.selector);
        staking.fundRewardsFromTreasury(1 ether);
    }

    function test_FundRewardsFromTreasury_SucceedsWhenTreasuryHasDonatedFunds() public {
        vm.deal(address(this), 5 ether);
        (bool ok,) = address(treasury).call{ value: 5 ether }("");
        assertTrue(ok);
        vm.prank(admin);
        staking.fundRewardsFromTreasury(5 ether);
        assertEq(address(staking).balance, 5 ether);
    }

    function test_Constructor_RevertsForZeroTreasury() public {
        vm.expectRevert(IStaking.ZeroAddress.selector);
        new Staking(admin, address(0));
    }

    function test_FundRewardsFromTreasury_RevertsForZeroAmount() public {
        vm.prank(admin);
        vm.expectRevert(IStaking.ZeroAmount.selector);
        staking.fundRewardsFromTreasury(0);
    }

    function test_FundRewards_IncreasesReserve() public {
        vm.deal(buyer, 2 ether);
        vm.prank(buyer);
        staking.fundRewards{ value: 2 ether }();
        assertEq(staking.rewardReserve(), 2 ether);
        assertEq(staking.rewardInventory(), 0);
    }

    function test_ConfigurationAcceptsValidBoundaries() public {
        vm.prank(admin);
        staking.configureBounds(1 ether, 2 ether);
        vm.prank(admin);
        staking.setCooldown(30 days);
        vm.prank(admin);
        staking.setEmergencyPenalty(5000);
        assertEq(staking.minimumStake(), 1 ether);
        assertEq(staking.maximumStake(), 2 ether);
        assertEq(staking.unstakeCooldown(), 30 days);
        assertEq(staking.emergencyPenaltyBps(), 5000);
    }

    function test_ScheduleRewardProgram_FutureStartIsScheduled() public {
        uint64 startAt = uint64(block.timestamp + 10);
        uint64 endAt = startAt + 100;
        vm.deal(admin, 10 ether);
        vm.prank(admin);
        staking.scheduleRewardProgram{ value: 10 ether }(startAt, endAt, 10 ether);
        assertEq(uint8(staking.currentRewardPhase()), uint8(IStaking.RewardPhase.Scheduled));
        assertEq(staking.rewardRate(), 0.1 ether);
    }

    function test_Unstake_RevertsWhenRecipientRejectsPayment() public {
        RejectingStaker rejecting = new RejectingStaker(staking);
        vm.deal(address(rejecting), 1 ether);
        rejecting.stake{ value: 1 ether }();
        vm.warp(block.timestamp + 1 days + 1);
        vm.expectRevert(IStaking.RewardTransferFailed.selector);
        rejecting.unstake(1 ether);
    }

    function test_ClaimReward_FullyFundedProgramNeverExhaustsInventory() public {
        vm.deal(buyer, 100 ether);
        vm.prank(buyer);
        staking.stake{ value: 100 ether }();
        vm.deal(admin, 100 ether);
        vm.prank(admin);
        staking.scheduleRewardProgram{ value: 100 ether }(
            uint64(block.timestamp), uint64(block.timestamp) + 100, 100 ether
        );
        vm.warp(block.timestamp + 100);
        vm.prank(buyer);
        staking.claimReward();
        assertEq(staking.pendingReward(buyer), 0);
    }

    function test_UnstakeAmountExactlyEqualToBalanceBoundary() public {
        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        staking.stake{ value: 1 ether }();
        vm.warp(block.timestamp + 1 days + 1);
        vm.prank(buyer);
        staking.unstake(1 ether);
        assertFalse(staking.getPosition(buyer).active);
    }

    function test_CompoundReward_RevertsWhenExceedingMaximumStake() public {
        vm.prank(admin);
        staking.configureBounds(0.01 ether, 10 ether);
        vm.deal(buyer, 9.5 ether);
        vm.prank(buyer);
        staking.stake{ value: 9.5 ether }();
        vm.deal(admin, 100 ether);
        vm.prank(admin);
        staking.scheduleRewardProgram{ value: 100 ether }(
            uint64(block.timestamp), uint64(block.timestamp) + 100, 100 ether
        );
        vm.warp(block.timestamp + 100);
        vm.prank(buyer);
        vm.expectRevert(IStaking.AmountTooLarge.selector);
        staking.compoundReward();
    }

    function test_Stake_RevertsWhenCooldownTimestampWouldOverflow() public {
        vm.warp(type(uint64).max);
        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        vm.expectRevert(IStaking.InvalidCooldown.selector);
        staking.stake{ value: 1 ether }();
        assertEq(staking.totalStaked(), 0);
    }

    function test_ScheduleRewardProgram_MovesUnreservedInventoryIntoReserve() public {
        vm.deal(address(this), 10 ether);
        (bool ok,) = address(staking).call{ value: 10 ether }("");
        assertTrue(ok);
        assertEq(staking.rewardInventory(), 10 ether);
        assertEq(staking.rewardReserve(), 0);
        uint64 startAt = uint64(block.timestamp + 10);
        vm.prank(admin);
        staking.scheduleRewardProgram(startAt, startAt + 100, 10 ether);
        assertEq(staking.rewardReserve(), 10 ether);
        assertEq(staking.rewardInventory(), 0);
        assertEq(staking.rewardRate(), 0.1 ether);
    }

    function test_Pause_KeepsClaimAndEmergencyExitOpen() public {
        vm.deal(buyer, 100 ether);
        vm.prank(buyer);
        staking.stake{ value: 100 ether }();
        _fundAndSchedule(100 ether, 100);
        vm.warp(block.timestamp + 100);
        vm.prank(admin);
        staking.pause();
        vm.prank(buyer);
        vm.expectRevert();
        staking.compoundReward();
        vm.prank(buyer);
        vm.expectRevert();
        staking.unstake(1 ether);
        uint256 balanceBefore = buyer.balance;
        vm.prank(buyer);
        staking.claimReward();
        assertGt(buyer.balance, balanceBefore);
        vm.prank(buyer);
        staking.emergencyUnstake();
        assertFalse(staking.getPosition(buyer).active);
        assertEq(staking.totalStaked(), 0);
    }

    function test_AdditionalStakeResetsCooldownForTheWholePosition() public {
        uint256 t0 = block.timestamp;
        vm.deal(buyer, 2 ether);
        vm.prank(buyer);
        staking.stake{ value: 1 ether }();
        vm.warp(t0 + 12 hours);
        vm.prank(buyer);
        staking.stake{ value: 1 ether }();
        vm.warp(t0 + 1 days + 1);
        vm.prank(buyer);
        vm.expectRevert(IStaking.CooldownActive.selector);
        staking.unstake(1 ether);
        vm.warp(t0 + 12 hours + 1 days + 1);
        vm.prank(buyer);
        staking.unstake(2 ether);
        assertEq(buyer.balance, 2 ether);
    }
}

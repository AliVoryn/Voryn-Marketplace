pragma solidity ^0.8.24;
import "../helpers/TestBase.sol";
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
        staking.stake{value: 0.001 ether}(); 
    }
    function test_Stake_RejectsZeroAndMaximumBoundary() public {
        vm.prank(buyer);
        vm.expectRevert(IStaking.ZeroAmount.selector);
        staking.stake();
        vm.prank(admin);
        staking.configureBounds(1 ether, 2 ether);
        vm.deal(buyer, 3 ether);
        vm.prank(buyer);
        staking.stake{value: 2 ether}();
        vm.prank(buyer);
        vm.expectRevert(IStaking.AmountTooLarge.selector);
        staking.stake{value: 1 wei}();
    }
    function test_StakeAndUnstakeRejectMissingOrExcessPosition() public {
        vm.prank(buyer);
        vm.expectRevert(IStaking.NoPosition.selector);
        staking.unstake(1 ether);
        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        staking.stake{value: 1 ether}();
        vm.warp(block.timestamp + 1 days + 1);
        vm.prank(buyer);
        vm.expectRevert(IStaking.InsufficientStake.selector);
        staking.unstake(1 ether + 1 wei);
    }
    function test_Stake_RecordsPositionAndTotal() public {
        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        staking.stake{value: 1 ether}();
        assertEq(staking.totalStaked(), 1 ether);
        assertEq(staking.getPosition(buyer).amount, 1 ether);
    }
    function test_Unstake_RevertsDuringCooldown() public {
        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        staking.stake{value: 1 ether}();
        vm.prank(buyer);
        vm.expectRevert(IStaking.CooldownActive.selector);
        staking.unstake(1 ether);
    }
    function test_Unstake_SucceedsAfterCooldown() public {
        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        staking.stake{value: 1 ether}();
        vm.warp(block.timestamp + 1 days + 1);
        uint256 before = buyer.balance;
        vm.prank(buyer);
        staking.unstake(1 ether);
        assertEq(buyer.balance, before + 1 ether);
    }
    function test_Unstake_PartialLeavesPositionActive() public {
        vm.deal(buyer, 2 ether);
        vm.prank(buyer);
        staking.stake{value: 2 ether}();
        vm.warp(block.timestamp + 1 days + 1);
        vm.prank(buyer);
        staking.unstake(1 ether);
        assertEq(staking.getPosition(buyer).amount, 1 ether);
        assertTrue(staking.getPosition(buyer).active);
    }
    function _fundAndSchedule(uint256 rewardAmount, uint64 duration) internal {
        vm.deal(admin, rewardAmount);
        vm.startPrank(admin);
        staking.scheduleRewardProgram{value: rewardAmount}(uint64(block.timestamp), uint64(block.timestamp) + duration, rewardAmount);
        vm.stopPrank();
    }
    function test_RewardAccrual_LinearOverTime() public {
        vm.deal(buyer, 100 ether);
        vm.prank(buyer);
        staking.stake{value: 100 ether}();
        _fundAndSchedule(100 ether, 100); 
        vm.warp(block.timestamp + 50);
        uint256 pending = staking.pendingReward(buyer);
        assertApproxEqAbs(pending, 50 ether, 1e12, "sole staker should accrue ~all emitted rewards");
    }
    function test_ClaimReward_PaysAndZeroes() public {
        vm.deal(buyer, 100 ether);
        vm.prank(buyer);
        staking.stake{value: 100 ether}();
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
        staking.stake{value: 100 ether}();
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
        staking.stake{value: 100 ether}();
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
        staking.stake{value: 1 ether}();
        uint256 before = staking.getPosition(buyer).amount;
        vm.prank(buyer);
        staking.claimReward();
        vm.prank(buyer);
        staking.compoundReward();
        assertEq(staking.getPosition(buyer).amount, before);
    }
    function test_regression_ReschedulingProgram_DoesNotLoseTailEmission() public {
        vm.deal(buyer, 100 ether);
        vm.prank(buyer);
        staking.stake{value: 100 ether}();
        _fundAndSchedule(100 ether, 100); 
        vm.warp(block.timestamp + 100); 
        _fundAndSchedule(50 ether, 50); 
        uint256 pending = staking.pendingReward(buyer);
        assertApproxEqAbs(pending, 100 ether, 1e12, "program 1's full tail emission must not be lost on reschedule");
    }
    function test_ScheduleRewardProgram_RevertsWhileActive() public {
        _fundAndSchedule(100 ether, 100);
        vm.deal(admin, 1 ether);
        vm.prank(admin);
        vm.expectRevert(IStaking.InvalidRewardProgram.selector);
        staking.scheduleRewardProgram{value: 1 ether}(uint64(block.timestamp), uint64(block.timestamp) + 10, 1 ether);
    }
    function test_ScheduleRewardProgram_RejectsInvalidRangeFundingAndRate() public {
        vm.deal(admin, 10 ether);
        vm.startPrank(admin);
        vm.expectRevert(IStaking.InvalidRewardProgram.selector);
        staking.scheduleRewardProgram(10, 10, 1 ether);
        vm.expectRevert(IStaking.InvalidRewardProgram.selector);
        staking.scheduleRewardProgram(11, 10, 1 ether);
        vm.expectRevert(IStaking.InvalidRewardProgram.selector);
        staking.scheduleRewardProgram(10, 20, 0);
        vm.expectRevert(IStaking.InvalidRewardProgram.selector);
        staking.scheduleRewardProgram(10, 20, 1 ether);
        vm.stopPrank();
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
        staking.stake{value: 1 ether}();
        vm.prank(admin);
        staking.unpause();
        vm.prank(buyer);
        staking.stake{value: 1 ether}();
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
        (bool ok,) = address(treasury).call{value: 5 ether}("");
        assertTrue(ok);
        vm.prank(admin);
        staking.fundRewardsFromTreasury(5 ether);
        assertEq(address(staking).balance, 5 ether);
    }
}

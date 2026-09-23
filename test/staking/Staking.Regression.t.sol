// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../support/TestBase.sol";

contract StakingRegressionTest is ProtocolTestBase {
    Staking internal staking;

    function setUp() public {
        _setUpCore();
        staking = _deployStaking(address(treasury));
    }

    function _fundAndSchedule(uint256 rewardAmount, uint64 duration) internal {
        vm.deal(admin, rewardAmount);
        vm.startPrank(admin);
        staking.scheduleRewardProgram{ value: rewardAmount }(
            uint64(block.timestamp), uint64(block.timestamp) + duration, rewardAmount
        );
        vm.stopPrank();
    }

    function test_ReschedulingProgram_DoesNotLoseTailEmission() public {
        vm.deal(buyer, 100 ether);
        vm.prank(buyer);
        staking.stake{ value: 100 ether }();
        _fundAndSchedule(100 ether, 100);
        vm.warp(block.timestamp + 100);
        _fundAndSchedule(50 ether, 50);
        uint256 pending = staking.pendingReward(buyer);
        assertApproxEqAbs(pending, 100 ether, 1e12, "program 1's full tail emission must not be lost on reschedule");
    }
}

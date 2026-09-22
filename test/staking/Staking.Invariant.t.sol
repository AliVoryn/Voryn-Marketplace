// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import "forge-std/StdInvariant.sol";

import "../support/TestBase.sol";

contract StakingInvariantHandler is Test {
    Staking internal staking;

    receive() external payable { }

    constructor(Staking staking_) {
        staking = staking_;
        vm.deal(address(this), 100 ether);
    }

    function stake(uint256 amountSeed) external {
        uint256 amount = bound(amountSeed, 0.01 ether, 5 ether);
        vm.deal(address(this), amount);
        try staking.stake{ value: amount }() { } catch { }
    }

    function unstake(uint256 amountSeed) external {
        IStaking.Position memory position = staking.getPosition(address(this));
        if (!position.active || position.amount == 0) return;
        vm.warp(block.timestamp + 1 days + 1);
        uint256 amount = bound(amountSeed, 1, position.amount);
        try staking.unstake(amount) { } catch { }
    }

    function claim() external {
        try staking.claimReward() { } catch { }
    }

    function compound() external {
        try staking.compoundReward() { } catch { }
    }

    function emergencyUnstake() external {
        try staking.emergencyUnstake() { } catch { }
    }

    function warp(uint256 secondsSeed) external {
        vm.warp(block.timestamp + bound(secondsSeed, 1, 1 days));
    }
}

contract StakingInvariantTest is ProtocolTestBase {
    Staking internal staking;
    StakingInvariantHandler internal handler;

    function setUp() public {
        _setUpCore();
        staking = _deployStaking(address(treasury));
        handler = new StakingInvariantHandler(staking);
        uint64 startAt = uint64(block.timestamp);
        uint64 endAt = startAt + 1000;
        uint256 rewardAmount = 1000 ether;
        vm.deal(admin, rewardAmount);
        vm.prank(admin);
        staking.scheduleRewardProgram{ value: rewardAmount }(startAt, endAt, rewardAmount);
        targetContract(address(handler));
    }

    function invariant_StakingBalanceBacksPrincipalRewardsAndReserve() public view {
        uint256 reserved = staking.totalStaked() + staking.totalRewardLiability() + staking.rewardReserve();
        assertGe(address(staking).balance, reserved);
    }
}

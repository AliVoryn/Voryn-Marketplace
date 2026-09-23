// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../support/TestBase.sol";

contract StakingSecurityTest is ProtocolTestBase {
    Staking internal staking;

    function setUp() public {
        _setUpCore();
        staking = _deployStaking(address(treasury));
    }

    function test_NonOwnerCannotChangeBoundsOrPenalty() public {
        vm.prank(attacker);
        vm.expectRevert();
        staking.configureBounds(1 ether, 2 ether);
        vm.prank(attacker);
        vm.expectRevert();
        staking.setEmergencyPenalty(100);
    }

    function test_RewardFundingCannotBeZero() public {
        vm.prank(staking.owner());
        vm.expectRevert(IStaking.ZeroAmount.selector);
        staking.fundRewards();
    }

    function test_EmergencyUnstakeClosesPosition() public {
        vm.deal(seller, 1 ether);
        vm.prank(seller);
        staking.stake{ value: 1 ether }();
        vm.prank(seller);
        staking.emergencyUnstake();
        IStaking.Position memory position = staking.getPosition(seller);
        assertFalse(position.active);
        assertEq(position.amount, 0);
    }
}

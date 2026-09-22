// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../support/TestBase.sol";

contract StakingFuzzTest is ProtocolTestBase {
    Staking internal staking;

    function setUp() public {
        _setUpCore();
        staking = _deployStaking(address(treasury));
    }

    function testFuzz_StakeUpdatesPositionAndTotal(uint96 rawAmount) public {
        uint256 amount = bound(uint256(rawAmount), 0.01 ether, 20 ether);
        vm.deal(seller, amount);
        vm.prank(seller);
        staking.stake{ value: amount }();
        IStaking.Position memory position = staking.getPosition(seller);
        assertEq(position.amount, amount);
        assertTrue(position.active);
        assertEq(staking.totalStaked(), amount);
    }

    function testFuzz_StakeThenEmergencyUnstakeLeavesNoPrincipal(uint96 rawAmount) public {
        uint256 amount = bound(uint256(rawAmount), 0.01 ether, 20 ether);
        vm.deal(seller, amount);
        vm.prank(seller);
        staking.stake{ value: amount }();
        uint256 before = seller.balance;
        vm.prank(seller);
        staking.emergencyUnstake();
        IStaking.Position memory position = staking.getPosition(seller);
        assertEq(position.amount, 0);
        assertFalse(position.active);
        assertEq(staking.totalStaked(), 0);
        assertLt(seller.balance, before + amount);
    }

    function testFuzz_InvalidCooldownAlwaysReverts(uint64 rawCooldown) public {
        uint64 cooldown = uint64(bound(uint256(rawCooldown), 30 days + 1, type(uint32).max));
        vm.prank(admin);
        vm.expectRevert(IStaking.InvalidCooldown.selector);
        staking.setCooldown(cooldown);
    }
}

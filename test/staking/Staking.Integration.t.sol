// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../support/TestBase.sol";

contract StakingIntegrationTest is ProtocolTestBase {
    Staking internal staking;

    function setUp() public {
        _setUpCore();
        staking = _deployStaking(address(treasury));
        vm.prank(admin);
        treasury.setAuthorizedPayer(address(staking), true);
        vm.deal(admin, 20 ether);
        vm.prank(admin);
        (bool success,) = address(treasury).call{ value: 20 ether }("");
        assertTrue(success);
    }

    function test_FundRewardsFromTreasuryMovesOnlyUnencumberedFunds() public {
        assertEq(treasury.availableBalance(), 20 ether);
        uint256 treasuryBefore = address(treasury).balance;

        vm.prank(admin);
        staking.fundRewardsFromTreasury(5 ether);

        assertEq(address(treasury).balance, treasuryBefore - 5 ether);
        assertEq(address(staking).balance, 5 ether);
        assertEq(staking.rewardReserve(), 5 ether);
        assertEq(treasury.availableBalance(), 15 ether);
    }

    function test_FundRewardsFromTreasuryCannotSpendLiabilityBackedFunds() public {
        vm.prank(admin);
        treasury.setAuthorizedPayer(admin, true);
        vm.deal(admin, 5 ether);
        vm.prank(admin);
        treasury.credit{ value: 5 ether }(buyer, keccak256("LIABILITY"));
        assertEq(address(treasury).balance, 25 ether);
        assertEq(treasury.availableBalance(), 20 ether);
        vm.prank(admin);
        vm.expectRevert(ITreasury.InsufficientAvailableBalance.selector);
        staking.fundRewardsFromTreasury(21 ether);
    }

    function test_RewardProgramUsesTreasuryFundingAndAccruesToStakeholders() public {
        vm.prank(admin);
        staking.fundRewardsFromTreasury(10 ether);

        vm.deal(buyer, 100 ether);
        vm.prank(buyer);
        staking.stake{ value: 100 ether }();

        uint64 startAt = uint64(block.timestamp + 1);
        uint64 endAt = startAt + 10;
        vm.prank(admin);
        staking.scheduleRewardProgram(startAt, endAt, 10 ether);

        vm.warp(startAt + 10);
        assertApproxEqAbs(staking.pendingReward(buyer), 10 ether, 1e12);
    }
}

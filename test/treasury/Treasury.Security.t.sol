// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../support/TestBase.sol";

contract TreasurySecurityTest is ProtocolTestBase {
    function setUp() public {
        _setUpCore();
    }

    function test_NonOwnerCannotAuthorizePayer() public {
        vm.prank(attacker);
        vm.expectRevert(ITreasury.Unauthorized.selector);
        treasury.setAuthorizedPayer(attacker, true);
    }

    function test_RescueCannotUseLiabilityBackedFunds() public {
        vm.prank(admin);
        treasury.setAuthorizedPayer(admin, true);
        vm.deal(admin, 1 ether);
        vm.prank(admin);
        treasury.credit{ value: 1 ether }(buyer, keccak256("LIABILITY"));
        vm.prank(admin);
        vm.expectRevert(ITreasury.NoRescueBalance.selector);
        treasury.emergencyRescue(payable(attacker), 1 ether);
    }

    function test_PayCannotExceedAvailableBalance() public {
        vm.prank(admin);
        treasury.setAuthorizedPayer(admin, true);
        vm.deal(admin, 1 ether);
        vm.prank(admin);
        treasury.credit{ value: 1 ether }(buyer, keccak256("LIABILITY"));
        vm.prank(admin);
        vm.expectRevert(ITreasury.InsufficientAvailableBalance.selector);
        treasury.pay(payable(attacker), 1, keccak256("PAY"));
    }
}

contract ReentrantTreasuryClaimant {
    Treasury internal immutable treasury;
    uint256 public reentrantSuccesses;

    constructor(Treasury treasury_) {
        treasury = treasury_;
    }

    function claim() external {
        treasury.withdrawClaimable();
    }

    receive() external payable {
        try treasury.withdrawClaimable() {
            reentrantSuccesses += 1;
        } catch { }
    }
}

contract TreasuryReentrancySecurityTest is ProtocolTestBase {
    function setUp() public {
        _setUpCore();
    }

    function test_WithdrawClaimableCannotBeReenteredToDrainOtherClaims() public {
        ReentrantTreasuryClaimant claimant = new ReentrantTreasuryClaimant(treasury);
        vm.deal(admin, 2 ether);
        vm.startPrank(admin);
        treasury.credit{ value: 1 ether }(address(claimant), keccak256("ATTACKER_CLAIM"));
        treasury.credit{ value: 1 ether }(buyer, keccak256("VICTIM_CLAIM"));
        vm.stopPrank();
        claimant.claim();
        assertEq(claimant.reentrantSuccesses(), 0);
        assertEq(address(claimant).balance, 1 ether);
        assertEq(address(treasury).balance, 1 ether);
        assertEq(treasury.claimable(buyer), 1 ether);
        assertEq(treasury.totalLiabilities(), 1 ether);
    }

    function test_UnauthorizedAccountsCannotConfigureTreasury() public {
        vm.startPrank(attacker);
        vm.expectRevert();
        treasury.setFactoryController(attacker);
        vm.expectRevert();
        treasury.setFeeRecipient(attacker);
        vm.expectRevert();
        treasury.setSpendingLimit(attacker, 1 ether);
        vm.expectRevert();
        treasury.emergencyRescue(payable(attacker), 1);
        vm.stopPrank();
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import "../support/TestBase.sol";

contract RejectingTreasuryRecipient {
    receive() external payable {
        revert();
    }
}

contract TreasuryAccountingTest is ProtocolTestBase {
    function setUp() public {
        _setUpCore();
    }

    function test_Credit_RevertsForUnauthorizedPayer() public {
        vm.deal(attacker, 1 ether);
        vm.prank(attacker);
        vm.expectRevert(ITreasury.Unauthorized.selector);
        treasury.credit{ value: 1 ether }(buyer, keccak256("CREDIT"));
    }

    function test_Credit_AccumulatesClaimableAndLiability() public {
        vm.deal(admin, 2 ether);
        vm.startPrank(admin);
        treasury.credit{ value: 1 ether }(seller, keccak256("SALE_A"));
        treasury.credit{ value: 1 ether }(seller, keccak256("SALE_B"));
        vm.stopPrank();
        assertEq(treasury.claimable(seller), 2 ether);
        assertEq(treasury.totalLiabilities(), 2 ether);
        assertEq(treasury.availableBalance(), 0);
    }

    function test_WithdrawClaimable_ReleasesExactLiability() public {
        vm.deal(admin, 1 ether);
        vm.prank(admin);
        treasury.credit{ value: 1 ether }(seller, keccak256("SALE"));
        uint256 before = seller.balance;
        vm.prank(seller);
        treasury.withdrawClaimable();
        assertEq(seller.balance, before + 1 ether);
        assertEq(treasury.claimable(seller), 0);
        assertEq(treasury.totalLiabilities(), 0);
    }

    function test_WithdrawClaimable_RevertsWhenNoClaimExists() public {
        vm.prank(buyer);
        vm.expectRevert(ITreasury.InsufficientAvailableBalance.selector);
        treasury.withdrawClaimable();
    }

    function test_Pay_UsesOnlyAvailableFunds() public {
        vm.deal(admin, 1 ether);
        vm.prank(admin);
        treasury.credit{ value: 1 ether }(seller, keccak256("SALE"));
        assertEq(treasury.availableBalance(), 0);
        vm.prank(admin);
        vm.expectRevert(ITreasury.InsufficientAvailableBalance.selector);
        treasury.pay(payable(buyer), 1 ether, keccak256("PAY"));
    }

    function test_Pay_SucceedsFromUnreservedETH() public {
        vm.deal(address(this), 1 ether);
        (bool success,) = address(treasury).call{ value: 1 ether }("");
        assertTrue(success);
        vm.prank(admin);
        treasury.pay(payable(buyer), 1 ether, keccak256("PAY"));
        assertEq(buyer.balance, 1 ether);
    }

    function test_Pay_AndRescueRejectZeroAndFailedRecipients() public {
        vm.deal(address(this), 2 ether);
        (bool success,) = address(treasury).call{ value: 2 ether }("");
        assertTrue(success);
        RejectingTreasuryRecipient rejecting = new RejectingTreasuryRecipient();

        vm.prank(admin);
        vm.expectRevert(ITreasury.ZeroAddress.selector);
        treasury.pay(payable(address(0)), 1 ether, keccak256("PAY"));

        vm.prank(admin);
        vm.expectRevert(ITreasury.PaymentFailed.selector);
        treasury.pay(payable(address(rejecting)), 1 ether, keccak256("PAY"));

        vm.prank(admin);
        vm.expectRevert(ITreasury.ZeroAddress.selector);
        treasury.emergencyRescue(payable(address(0)), 1 ether);

        vm.prank(admin);
        vm.expectRevert(ITreasury.NoRescueBalance.selector);
        treasury.emergencyRescue(payable(buyer), 3 ether);

        vm.prank(admin);
        vm.expectRevert(ITreasury.PaymentFailed.selector);
        treasury.emergencyRescue(payable(address(rejecting)), 1 ether);
    }

    function test_Credit_RevertsForZeroAccountAndZeroValue() public {
        vm.deal(admin, 1 ether);
        vm.prank(admin);
        vm.expectRevert(ITreasury.ZeroAddress.selector);
        treasury.credit{ value: 1 ether }(address(0), keccak256("CREDIT"));

        vm.prank(admin);
        vm.expectRevert(ITreasury.ZeroAmount.selector);
        treasury.credit{ value: 0 }(seller, keccak256("CREDIT"));
    }

    function test_PayAndRescueRejectZeroAmount() public {
        vm.prank(admin);
        vm.expectRevert(ITreasury.ZeroAmount.selector);
        treasury.pay(payable(buyer), 0, keccak256("PAY"));

        vm.prank(admin);
        vm.expectRevert(ITreasury.ZeroAmount.selector);
        treasury.emergencyRescue(payable(buyer), 0);
    }

    function test_Pay_RevertsForUnauthorizedPayer() public {
        vm.deal(address(this), 1 ether);
        (bool success,) = address(treasury).call{ value: 1 ether }("");
        assertTrue(success);
        vm.prank(attacker);
        vm.expectRevert(ITreasury.Unauthorized.selector);
        treasury.pay(payable(buyer), 1 ether, keccak256("PAY"));
    }

    function test_SpendingLimit_EnforcesAndResetsAfterFullWindow() public {
        vm.deal(address(this), 3 ether);
        (bool success,) = address(treasury).call{ value: 3 ether }("");
        assertTrue(success);
        vm.prank(admin);
        treasury.setSpendingLimit(admin, 1 ether);
        vm.prank(admin);
        treasury.pay(payable(buyer), 1 ether, keccak256("PAY_1"));
        assertEq(treasury.remainingDailyAllowance(admin), 0);
        vm.prank(admin);
        vm.expectRevert(ITreasury.DailyLimitExceeded.selector);
        treasury.pay(payable(buyer), 1 wei, keccak256("PAY_2"));
        vm.warp(block.timestamp + 1 days);
        assertEq(treasury.remainingDailyAllowance(admin), 1 ether);
        vm.prank(admin);
        treasury.pay(payable(buyer), 1 ether, keccak256("PAY_3"));
    }

    function test_SetSpendingLimit_ResetsExistingWindow() public {
        vm.deal(address(this), 2 ether);
        (bool success,) = address(treasury).call{ value: 2 ether }("");
        assertTrue(success);
        vm.prank(admin);
        treasury.setSpendingLimit(admin, 1 ether);
        vm.prank(admin);
        treasury.pay(payable(buyer), 1 ether, keccak256("PAY_1"));
        vm.prank(admin);
        treasury.setSpendingLimit(admin, 2 ether);
        assertEq(treasury.remainingDailyAllowance(admin), 2 ether);
    }

    function test_SetFactoryController_ChangesFactoryAuthorization() public {
        address controller = makeAddr("treasuryFactoryController");
        vm.prank(admin);
        treasury.setFactoryController(controller);
        assertEq(treasury.factoryController(), controller);

        vm.prank(controller);
        treasury.setAuthorizedPayer(attacker, true);
        assertTrue(treasury.authorizedPayer(attacker));

        vm.prank(controller);
        treasury.setAuthorizedPayer(attacker, false);
        assertFalse(treasury.authorizedPayer(attacker));
    }

    function test_SetFactoryController_CanRevokeFactoryPrivilege() public {
        address controller = makeAddr("treasuryFactoryController");
        vm.prank(admin);
        treasury.setFactoryController(controller);
        vm.prank(controller);
        treasury.setAuthorizedPayer(attacker, true);
        vm.prank(admin);
        treasury.setFactoryController(address(0));
        vm.prank(controller);
        vm.expectRevert(ITreasury.Unauthorized.selector);
        treasury.setAuthorizedPayer(attacker, false);
    }

    function test_SetAuthorizedPayer_RemainsOwnerControlledWithoutFactoryController() public {
        vm.prank(attacker);
        vm.expectRevert(ITreasury.Unauthorized.selector);
        treasury.setAuthorizedPayer(attacker, true);
        vm.prank(admin);
        treasury.setAuthorizedPayer(attacker, true);
        assertTrue(treasury.authorizedPayer(attacker));
    }

    function test_Constructor_RevertsForZeroFeeRecipient() public {
        vm.expectRevert(ITreasury.ZeroAddress.selector);
        new Treasury(admin, address(0), address(0));
    }

    function test_ForcedETH_IsAvailableForPaymentAndDoesNotCreateLiability() public {
        vm.deal(address(this), 1 ether);
        (bool success,) = address(treasury).call{ value: 1 ether }("");
        assertTrue(success);
        assertEq(treasury.totalLiabilities(), 0);
        assertEq(treasury.availableBalance(), 1 ether);
    }

    function _donate(uint256 amount) internal {
        vm.deal(address(this), amount);
        (bool success,) = address(treasury).call{ value: amount }("");
        assertTrue(success);
    }

    function test_SetFeeRecipient_UpdatesRecipientAndEmits() public {
        address next = makeAddr("nextFeeRecipient");
        vm.expectEmit(true, true, false, false, address(treasury));
        emit ITreasury.FeeRecipientUpdated(feeRecipient, next);
        vm.prank(admin);
        treasury.setFeeRecipient(next);
        assertEq(treasury.feeRecipient(), next);
        assertEq(treasury.feeRecipientForProtocol(), next);
    }

    function test_SetFeeRecipient_RevertsForZeroAddressAndNonOwner() public {
        vm.prank(admin);
        vm.expectRevert(ITreasury.ZeroAddress.selector);
        treasury.setFeeRecipient(address(0));
        vm.prank(attacker);
        vm.expectRevert();
        treasury.setFeeRecipient(attacker);
        assertEq(treasury.feeRecipient(), feeRecipient);
    }

    function test_SpendingLimitOf_ReportsConfiguredLimitAndRejectsZeroPayer() public {
        assertEq(treasury.spendingLimitOf(admin), 0);
        vm.prank(admin);
        treasury.setSpendingLimit(admin, 3 ether);
        assertEq(treasury.spendingLimitOf(admin), 3 ether);
        vm.prank(admin);
        vm.expectRevert(ITreasury.ZeroAddress.selector);
        treasury.setSpendingLimit(address(0), 1 ether);
        vm.prank(attacker);
        vm.expectRevert();
        treasury.setSpendingLimit(admin, 1 ether);
    }

    function test_RemainingDailyAllowance_CoversEveryBranch() public {
        _donate(3 ether);
        assertEq(treasury.remainingDailyAllowance(admin), type(uint256).max);
        vm.prank(admin);
        treasury.setSpendingLimit(admin, 2 ether);
        assertEq(treasury.remainingDailyAllowance(admin), 2 ether);
        vm.prank(admin);
        treasury.pay(payable(buyer), 1 ether, keccak256("PAY_1"));
        assertEq(treasury.remainingDailyAllowance(admin), 1 ether);
        vm.prank(admin);
        treasury.pay(payable(buyer), 1 ether, keccak256("PAY_2"));
        assertEq(treasury.remainingDailyAllowance(admin), 0);
        vm.warp(block.timestamp + 1 days);
        assertEq(treasury.remainingDailyAllowance(admin), 2 ether);
    }

    function test_SetSpendingLimit_ZeroRemovesTheLimit() public {
        _donate(3 ether);
        vm.prank(admin);
        treasury.setSpendingLimit(admin, 1 ether);
        vm.prank(admin);
        treasury.pay(payable(buyer), 1 ether, keccak256("PAY_1"));
        vm.prank(admin);
        treasury.setSpendingLimit(admin, 0);
        vm.prank(admin);
        treasury.pay(payable(buyer), 2 ether, keccak256("PAY_2"));
        assertEq(buyer.balance, 3 ether);
    }

    function test_EmergencyRescue_MovesOnlyFreeFundsAndEmits() public {
        _donate(2 ether);
        vm.expectEmit(true, false, false, true, address(treasury));
        emit ITreasury.EmergencyRescue(buyer, 1 ether);
        vm.prank(admin);
        treasury.emergencyRescue(payable(buyer), 1 ether);
        assertEq(buyer.balance, 1 ether);
        assertEq(treasury.availableBalance(), 1 ether);
        vm.prank(attacker);
        vm.expectRevert();
        treasury.emergencyRescue(payable(attacker), 1 ether);
    }

    function test_CreditAndWithdrawEmitAccountingEvents() public {
        bytes32 reason = keccak256("EVENT_CREDIT");
        vm.deal(admin, 1 ether);
        vm.expectEmit(true, true, false, true, address(treasury));
        emit ITreasury.Credit(seller, 1 ether, reason);
        vm.prank(admin);
        treasury.credit{ value: 1 ether }(seller, reason);
        vm.expectEmit(true, true, false, true, address(treasury));
        emit ITreasury.Payment(seller, 1 ether, keccak256("CLAIM"));
        vm.prank(seller);
        treasury.withdrawClaimable();
    }
}

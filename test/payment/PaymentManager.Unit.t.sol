// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import "../support/TestBase.sol";

contract PaymentManagerAccountingTest is ProtocolTestBase {
    function setUp() public {
        _setUpCore();
        vm.prank(admin);
        paymentManager.setCreditor(admin, true);
    }

    function test_Credit_RevertsForUnauthorizedCreditor() public {
        vm.deal(attacker, 1 ether);
        vm.prank(attacker);
        vm.expectRevert(IPaymentManager.Unauthorized.selector);
        paymentManager.credit{ value: 1 ether }(buyer, keccak256("REFUND"));
    }

    function test_Credit_Accumulates() public {
        vm.deal(admin, 2 ether);
        vm.startPrank(admin);
        paymentManager.credit{ value: 1 ether }(buyer, keccak256("A"));
        paymentManager.credit{ value: 1 ether }(buyer, keccak256("B"));
        vm.stopPrank();
        assertEq(paymentManager.claimable(buyer), 2 ether);
        assertEq(paymentManager.totalClaimable(), 2 ether);
    }

    function test_Withdraw_PaysExactClaimableAndZeroesIt() public {
        vm.deal(admin, 1 ether);
        vm.prank(admin);
        paymentManager.credit{ value: 1 ether }(buyer, keccak256("REFUND"));
        uint256 before = buyer.balance;
        vm.prank(buyer);
        paymentManager.withdraw();
        assertEq(buyer.balance, before + 1 ether);
        assertEq(paymentManager.claimable(buyer), 0);
        assertEq(paymentManager.totalClaimable(), 0);
    }

    function test_Withdraw_RevertsWhenNothingClaimable() public {
        vm.prank(buyer);
        vm.expectRevert(IPaymentManager.NothingToWithdraw.selector);
        paymentManager.withdraw();
    }

    function testFuzz_Invariant_BalanceCoversAggregateClaimable(uint96 a1, uint96 a2) public {
        vm.deal(admin, uint256(a1) + uint256(a2));
        vm.startPrank(admin);
        if (a1 > 0) paymentManager.credit{ value: a1 }(buyer, keccak256("A"));
        if (a2 > 0) paymentManager.credit{ value: a2 }(buyer2, keccak256("B"));
        vm.stopPrank();
        uint256 aggregateClaimable = paymentManager.claimable(buyer) + paymentManager.claimable(buyer2);
        assertGe(address(paymentManager).balance, aggregateClaimable);
    }

    function test_DirectETH_Reverts() public {
        vm.deal(attacker, 1 ether);
        vm.prank(attacker);
        (bool ok,) = address(paymentManager).call{ value: 1 ether }("");
        assertFalse(ok, "direct ETH transfers must be rejected");
    }

    function test_Credit_RevertsForZeroAccount() public {
        vm.deal(admin, 1 ether);
        vm.prank(admin);
        vm.expectRevert(IPaymentManager.ZeroAddress.selector);
        paymentManager.credit{ value: 1 ether }(address(0), keccak256("A"));
    }

    function test_Credit_RevertsForZeroValue() public {
        vm.prank(admin);
        vm.expectRevert(IPaymentManager.ZeroAmount.selector);
        paymentManager.credit{ value: 0 }(buyer, keccak256("A"));
    }

    function test_SetCreditor_RevertsForZeroAddress() public {
        vm.prank(admin);
        vm.expectRevert(IPaymentManager.ZeroAddress.selector);
        paymentManager.setCreditor(address(0), true);
    }

    function test_SetCreditor_RevertsForNonOwner() public {
        vm.prank(attacker);
        vm.expectRevert();
        paymentManager.setCreditor(attacker, true);
    }

    function test_SetCreditor_RevocationBlocksFurtherCredits() public {
        vm.prank(admin);
        paymentManager.setCreditor(admin, false);
        vm.deal(admin, 1 ether);
        vm.prank(admin);
        vm.expectRevert(IPaymentManager.Unauthorized.selector);
        paymentManager.credit{ value: 1 ether }(buyer, keccak256("A"));
    }

    function test_Withdraw_RevertsOnSecondCallAfterFirstDrainsBalance() public {
        vm.deal(admin, 1 ether);
        vm.prank(admin);
        paymentManager.credit{ value: 1 ether }(buyer, keccak256("A"));
        vm.prank(buyer);
        paymentManager.withdraw();
        vm.prank(buyer);
        vm.expectRevert(IPaymentManager.NothingToWithdraw.selector);
        paymentManager.withdraw();
    }

    function test_AccountingEventsAreEmitted() public {
        bytes32 reason = keccak256("EVENTS");
        vm.expectEmit(true, false, false, true, address(paymentManager));
        emit IPaymentManager.CreditorAuthorizationChanged(buyer2, true);
        vm.prank(admin);
        paymentManager.setCreditor(buyer2, true);

        vm.deal(admin, 1 ether);
        vm.expectEmit(true, true, false, true, address(paymentManager));
        emit IPaymentManager.PaymentCredited(buyer, 1 ether, reason);
        vm.prank(admin);
        paymentManager.credit{ value: 1 ether }(buyer, reason);

        vm.expectEmit(true, false, false, true, address(paymentManager));
        emit IPaymentManager.PaymentWithdrawn(buyer, 1 ether);
        vm.prank(buyer);
        paymentManager.withdraw();
    }

    function test_FactoryController_CanManageCreditorsUntilRevoked() public {
        address controller = makeAddr("paymentController");
        vm.expectEmit(true, false, false, false, address(paymentManager));
        emit IPaymentManager.FactoryControllerUpdated(controller);
        vm.prank(admin);
        paymentManager.setFactoryController(controller);
        assertEq(paymentManager.factoryController(), controller);
        vm.prank(controller);
        paymentManager.setCreditor(buyer, true);
        assertTrue(paymentManager.authorizedCreditor(buyer));
        vm.prank(admin);
        paymentManager.setFactoryController(address(0));
        vm.prank(controller);
        vm.expectRevert(IPaymentManager.Unauthorized.selector);
        paymentManager.setCreditor(buyer2, true);
    }
}

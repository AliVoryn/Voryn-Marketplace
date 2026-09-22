// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../support/TestBase.sol";

contract RevertingPaymentRecipient {
    PaymentManager internal immutable manager;

    constructor(PaymentManager manager_) {
        manager = manager_;
    }

    receive() external payable {
        revert();
    }

    function withdraw() external {
        manager.withdraw();
    }
}

contract PaymentManagerRegressionTest is ProtocolTestBase {
    function setUp() public {
        _setUpCore();
        vm.prank(admin);
        paymentManager.setCreditor(admin, true);
    }

    function test_FailedWithdrawalRollsBackClaimAccounting() public {
        RevertingPaymentRecipient recipient = new RevertingPaymentRecipient(paymentManager);
        vm.deal(admin, 1 ether);
        vm.prank(admin);
        paymentManager.credit{ value: 1 ether }(address(recipient), keccak256("REFUND"));

        vm.expectRevert(IPaymentManager.PaymentFailed.selector);
        recipient.withdraw();

        assertEq(paymentManager.claimable(address(recipient)), 1 ether);
        assertEq(paymentManager.totalClaimable(), 1 ether);
        assertEq(address(paymentManager).balance, 1 ether);
    }
}

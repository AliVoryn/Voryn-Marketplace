// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../support/TestBase.sol";

contract PaymentManagerSecurityTest is ProtocolTestBase {
    function setUp() public {
        _setUpCore();
    }

    function test_NonOwnerCannotAuthorizeCreditor() public {
        vm.prank(attacker);
        vm.expectRevert(IPaymentManager.Unauthorized.selector);
        paymentManager.setCreditor(attacker, true);
    }

    function test_NonOwnerCannotChangeFactoryController() public {
        vm.prank(attacker);
        vm.expectRevert();
        paymentManager.setFactoryController(attacker);
    }

    function test_CreditorCannotRedirectClaimToZeroAddress() public {
        vm.prank(admin);
        paymentManager.setCreditor(admin, true);
        vm.deal(admin, 1 ether);
        vm.prank(admin);
        vm.expectRevert(IPaymentManager.ZeroAddress.selector);
        paymentManager.credit(address(0), keccak256("BAD"));
    }
}

contract ReentrantPaymentRecipient {
    PaymentManager internal immutable manager;
    uint256 public reentrantSuccesses;

    constructor(PaymentManager manager_) {
        manager = manager_;
    }

    function claim() external {
        manager.withdraw();
    }

    receive() external payable {
        try manager.withdraw() {
            reentrantSuccesses += 1;
        } catch { }
    }
}

contract PaymentManagerReentrancySecurityTest is ProtocolTestBase {
    function setUp() public {
        _setUpCore();
        vm.prank(admin);
        paymentManager.setCreditor(admin, true);
    }

    function test_WithdrawCannotBeReenteredToDrainOtherClaims() public {
        ReentrantPaymentRecipient recipient = new ReentrantPaymentRecipient(paymentManager);
        vm.deal(admin, 2 ether);
        vm.startPrank(admin);
        paymentManager.credit{ value: 1 ether }(address(recipient), keccak256("ATTACKER"));
        paymentManager.credit{ value: 1 ether }(buyer, keccak256("VICTIM"));
        vm.stopPrank();
        recipient.claim();
        assertEq(recipient.reentrantSuccesses(), 0);
        assertEq(address(recipient).balance, 1 ether);
        assertEq(address(paymentManager).balance, 1 ether);
        assertEq(paymentManager.claimable(buyer), 1 ether);
        assertEq(paymentManager.totalClaimable(), 1 ether);
    }
}

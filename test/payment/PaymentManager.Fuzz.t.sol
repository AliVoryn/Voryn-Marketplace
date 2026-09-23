// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../support/TestBase.sol";

contract PaymentManagerFuzzTest is ProtocolTestBase {
    function setUp() public {
        _setUpCore();
        vm.prank(admin);
        paymentManager.setCreditor(admin, true);
    }

    function testFuzz_CreditAndWithdrawConserveAmount(uint96 rawAmount) public {
        uint256 amount = bound(uint256(rawAmount), 1, 20 ether);
        vm.deal(admin, amount);
        vm.prank(admin);
        paymentManager.credit{ value: amount }(buyer, keccak256("FUZZ"));
        assertEq(paymentManager.claimable(buyer), amount);
        assertEq(paymentManager.totalClaimable(), amount);
        vm.prank(buyer);
        paymentManager.withdraw();
        assertEq(paymentManager.claimable(buyer), 0);
        assertEq(paymentManager.totalClaimable(), 0);
    }

    function testFuzz_MultipleCreditsAggregate(uint96 firstRaw, uint96 secondRaw) public {
        uint256 first = bound(uint256(firstRaw), 1, 5 ether);
        uint256 second = bound(uint256(secondRaw), 1, 5 ether);
        vm.deal(admin, first + second);
        vm.prank(admin);
        paymentManager.credit{ value: first }(buyer, keccak256("ONE"));
        vm.prank(admin);
        paymentManager.credit{ value: second }(buyer, keccak256("TWO"));
        assertEq(paymentManager.claimable(buyer), first + second);
        assertEq(paymentManager.totalClaimable(), first + second);
    }
}

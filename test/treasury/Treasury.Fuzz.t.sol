// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../support/TestBase.sol";

contract TreasuryFuzzTest is ProtocolTestBase {
    function setUp() public {
        _setUpCore();
        vm.prank(admin);
        treasury.setAuthorizedPayer(admin, true);
    }

    function testFuzz_CreditAndClaimableConserveValue(uint96 rawAmount) public {
        uint256 amount = bound(uint256(rawAmount), 1, 20 ether);
        vm.deal(admin, amount);
        vm.prank(admin);
        treasury.credit{ value: amount }(buyer, keccak256("FUZZ"));
        assertEq(treasury.claimable(buyer), amount);
        assertEq(treasury.availableBalance(), 0);
    }

    function testFuzz_PayUsesOnlyUnreservedFunds(uint96 rawAmount) public {
        uint256 amount = bound(uint256(rawAmount), 1, 5 ether);
        vm.deal(address(treasury), amount);
        vm.prank(admin);
        treasury.pay(payable(buyer), amount, keccak256("PAY"));
        assertEq(treasury.availableBalance(), 0);
        assertEq(buyer.balance, amount);
    }
}

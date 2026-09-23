// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import "forge-std/Test.sol";
import "../../src/libraries/AccountingMath.sol";

contract AccountingMathTest is Test {
    function test_safeSubtract_ClampsAtZero() public pure {
        assertEq(AccountingMath.safeSubtract(5, 10), 0);
    }

    function test_safeSubtract_NormalCase() public pure {
        assertEq(AccountingMath.safeSubtract(10, 4), 6);
    }

    function test_available_ClampsAtZeroWhenLiabilitiesExceedBalance() public pure {
        assertEq(AccountingMath.available(5, 10), 0);
    }

    function testFuzz_available_NeverExceedsBalance(uint256 balance, uint256 liabilities) public pure {
        assertLe(AccountingMath.available(balance, liabilities), balance);
    }

    function test_safeSubtract_ExactBoundaryEqualIsZero() public pure {
        assertEq(AccountingMath.safeSubtract(7, 7), 0);
    }

    function test_available_ExactBoundaryEqualIsZero() public pure {
        assertEq(AccountingMath.available(10, 10), 0);
    }

    function test_available_NormalCaseSubtracts() public pure {
        assertEq(AccountingMath.available(10, 3), 7);
    }
}

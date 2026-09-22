// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import "forge-std/Test.sol";
import "../../src/libraries/ListingMath.sol";

contract ListingMathTest is Test {
    function test_activeAt_NeverExpiresWhenZero() public pure {
        assertTrue(ListingMath.activeAt(type(uint64).max, 0));
    }

    function test_activeAt_FalseAtExactExpiry() public pure {
        assertFalse(ListingMath.activeAt(100, 100));
    }

    function test_isStale_TrueAtExactExpiry() public pure {
        assertTrue(ListingMath.isStale(100, 100));
    }

    function test_isStale_FalseWhenNoExpiry() public pure {
        assertFalse(ListingMath.isStale(type(uint64).max, 0));
    }

    function testFuzz_activeAt_isStale_AreComplementary(uint64 nowTs, uint64 expiresAt) public pure {
        vm.assume(expiresAt != 0);
        assertTrue(ListingMath.activeAt(nowTs, expiresAt) != ListingMath.isStale(nowTs, expiresAt));
    }
}

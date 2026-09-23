// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import "forge-std/Test.sol";
import "../../src/libraries/PhaseLogic.sol";

contract PhaseLogicTest is Test {
    function test_afterEnd_ExactBoundaryIsTrue() public pure {
        assertTrue(PhaseLogic.afterEnd(100, 100));
    }

    function test_afterEnd_OneBeforeIsFalse() public pure {
        assertFalse(PhaseLogic.afterEnd(99, 100));
    }
}

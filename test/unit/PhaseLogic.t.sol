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
    function test_inWindow_TrueJustInsideWindow() public pure {
        assertTrue(PhaseLogic.inWindow(95, 100, 10));
    }
    function test_inWindow_FalseExactlyAtDeadline() public pure {
        assertFalse(PhaseLogic.inWindow(100, 100, 10));
    }
    function test_inWindow_FalseOutsideWindow() public pure {
        assertFalse(PhaseLogic.inWindow(50, 100, 10));
    }
}

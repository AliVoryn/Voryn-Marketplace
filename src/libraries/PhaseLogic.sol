pragma solidity ^0.8.24;
library PhaseLogic {
    function afterEnd(uint64 nowTs, uint64 deadline) internal pure returns (bool) {
        return nowTs >= deadline;
    }
    function inWindow(uint64 nowTs, uint64 deadline, uint64 window) internal pure returns (bool) {
        return nowTs < deadline && deadline - nowTs <= window;
    }
}

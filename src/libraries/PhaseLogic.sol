// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

library PhaseLogic {
    function afterEnd(uint64 nowTs, uint64 deadline) internal pure returns (bool) {
        return nowTs >= deadline;
    }
}

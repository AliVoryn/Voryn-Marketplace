// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

library AccountingMath {
    function safeSubtract(uint a, uint b) internal pure returns (uint) {
        return a >= b ? a - b : 0;
    }

    function available(uint balance, uint liabilities) internal pure returns (uint) {
        return balance > liabilities ? balance - liabilities : 0;
    }
}

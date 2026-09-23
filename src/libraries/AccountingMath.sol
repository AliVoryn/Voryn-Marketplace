// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

library AccountingMath {
    function safeSubtract(uint256 a, uint256 b) internal pure returns (uint256) {
        return a >= b ? a - b : 0;
    }

    function available(uint256 balance, uint256 liabilities) internal pure returns (uint256) {
        return balance > liabilities ? balance - liabilities : 0;
    }
}

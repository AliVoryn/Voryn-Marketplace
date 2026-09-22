// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
pragma experimental SMTChecker;

import "../../src/libraries/FeeMath.sol";

contract SymbolicFeeMathHarness {
    function feeNeverExceedsAmount(uint256 amount, uint16 bps) external pure returns (bool) {
        if (bps > 10_000) return true;
        uint256 feeAmount = FeeMath.fee(amount, bps);
        assert(feeAmount <= amount);
        return true;
    }

    function splitConservesAmount(uint256 amount, uint16 bps) external pure returns (bool) {
        if (bps > 10_000) return true;
        (uint256 feeAmount, uint256 sellerAmount) = FeeMath.split(amount, bps);
        assert(feeAmount + sellerAmount == amount);
        return true;
    }
}

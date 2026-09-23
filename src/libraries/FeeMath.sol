// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

library FeeMath {
    uint256 internal constant BPS = 10_000;
    error FeeTooHigh();

    function fee(uint256 amount, uint16 bps) internal pure returns (uint256) {
        if (bps > BPS) revert FeeTooHigh();
        return amount * bps / BPS;
    }

    function split(uint256 amount, uint16 protocolBps)
        internal
        pure
        returns (uint256 protocolFee, uint256 sellerAmount)
    {
        protocolFee = fee(amount, protocolBps);
        sellerAmount = amount - protocolFee;
    }
}

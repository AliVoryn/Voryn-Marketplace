pragma solidity ^0.8.24;
library FeeMath {
    uint internal constant BPS = 10_000;
    error FeeTooHigh();
    function fee(uint amount, uint16 bps) internal pure returns (uint) {
        if (bps > BPS) revert FeeTooHigh();
        return amount * bps / BPS;
    }
    function split(uint amount, uint16 protocolBps) internal pure returns (uint protocolFee, uint sellerAmount) {
        protocolFee = fee(amount, protocolBps);
        sellerAmount = amount - protocolFee;
    }
}

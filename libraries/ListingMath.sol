// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

library ListingMath {
    uint internal constant BPS = 10_000;

    function protocolFee(uint amount, uint16 bps) internal pure returns (uint) {
        return amount * bps / BPS;
    }

    function sellerProceeds(uint amount, uint16 feeBps) internal pure returns (uint) {
        return amount - protocolFee(amount, feeBps);
    }

    function activeAt(uint64 nowTs, uint64 expiresAt) internal pure returns (bool) {
        return expiresAt == 0 || nowTs < expiresAt;
    }

    function isStale(uint64 nowTs, uint64 expiresAt) internal pure returns (bool) {
        return expiresAt != 0 && nowTs >= expiresAt;
    }
}

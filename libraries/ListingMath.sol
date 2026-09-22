// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

library ListingMath {
    function activeAt(uint64 nowTs, uint64 expiresAt) internal pure returns (bool) {
        return expiresAt == 0 || nowTs < expiresAt;
    }

    function isStale(uint64 nowTs, uint64 expiresAt) internal pure returns (bool) {
        return expiresAt != 0 && nowTs >= expiresAt;
    }
}

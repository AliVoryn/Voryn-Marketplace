// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
pragma experimental SMTChecker;

import "../../src/libraries/AuctionMath.sol";

contract SymbolicAuctionMathHarness {
    function minimumBidMonotonic(uint256 highestBid, uint256 increment) external pure returns (bool) {
        if (type(uint256).max - highestBid < increment) return true;
        uint256 nextBid = AuctionMath.nextMinimumBid(highestBid, increment);
        assert(nextBid >= highestBid);
        return true;
    }

    function extensionRespectsCap(uint64 currentTime, uint64 endTime, uint64 window, uint8 used, uint8 max) external pure returns (bool) {
        bool extend = AuctionMath.shouldExtend(currentTime, endTime, window, used, max);
        if (used >= max || currentTime >= endTime) assert(!extend);
        return true;
    }
}

pragma solidity ^0.8.24;
library AuctionMath {
    function nextMinimumBid(uint highestBid, uint increment) internal pure returns (uint) {
        return highestBid + increment;
    }
    function shouldExtend(
        uint64 currentTime,
        uint64 endTime,
        uint64 window,
        uint8 used,
        uint8 max
    ) internal pure returns (bool) {
        if (used >= max) return false;
        if (currentTime >= endTime) return false;
        return endTime - currentTime <= window;
    }
}

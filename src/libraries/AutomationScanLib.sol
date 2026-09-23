// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

library AutomationScanLib {
    uint256 internal constant MAX_SCAN = 500;

    uint256 internal constant MAX_ITEMS = 100;

    function window(uint256 total, uint256 cycle, uint256 maxScan)
        internal
        pure
        returns (uint256 startId, uint256 endId)
    {
        if (total == 0 || maxScan == 0) return (1, 1);
        if (maxScan > MAX_SCAN) maxScan = MAX_SCAN;
        uint256 span = total < maxScan ? total : maxScan;
        uint256 windows = (total + span - 1) / span;
        startId = 1 + (cycle % windows) * span;
        endId = startId + span;
        if (endId > total + 1) endId = total + 1;
    }

    function capacity(uint256 maxItems, uint256 startId, uint256 endId) internal pure returns (uint256 cap) {
        if (maxItems > MAX_ITEMS) maxItems = MAX_ITEMS;
        cap = endId - startId;
        if (maxItems < cap) cap = maxItems;
    }
}

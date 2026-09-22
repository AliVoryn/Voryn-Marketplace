pragma solidity ^0.8.24;
import "../interfaces/IBlindAuction.sol";
library AuctionPhaseLib {
    struct Clock {
        uint256 biddingEnd;
        uint256 revealEnd;
        uint256 revealExtensionsUsed;
        bool ended;
        bool cancelled;
    }
    function currentPhase(Clock storage self) internal view returns (IBlindAuction.Phase) {
        if (self.cancelled) return IBlindAuction.Phase.Cancelled;
        if (self.ended) return IBlindAuction.Phase.Ended;
        if (block.timestamp < self.biddingEnd) return IBlindAuction.Phase.Bidding;
        if (block.timestamp < self.revealEnd) return IBlindAuction.Phase.Reveal;
        return IBlindAuction.Phase.AwaitingFinalization;
    }
    function requirePhase(Clock storage self, IBlindAuction.Phase required) internal view {
        IBlindAuction.Phase current = currentPhase(self);
        if (current != required) revert IBlindAuction.InvalidPhase(current, required);
    }
    function timeRemaining(Clock storage self) internal view returns (uint256) {
        IBlindAuction.Phase current = currentPhase(self);
        if (current == IBlindAuction.Phase.Bidding) return self.biddingEnd - block.timestamp;
        if (current == IBlindAuction.Phase.Reveal) return self.revealEnd - block.timestamp;
        return 0;
    }
    function tryExtendReveal(Clock storage self, uint256 extendedWindow, uint256 extensionTime, uint256 maxExtensions)
        internal
        returns (bool extended)
    {
        if (self.revealEnd > block.timestamp && (self.revealEnd - block.timestamp) < extendedWindow && self.revealExtensionsUsed < maxExtensions) {
            self.revealEnd += extensionTime;
            self.revealExtensionsUsed += 1;
            emit IBlindAuction.RevealDeadlineExtended(self.revealEnd, self.revealExtensionsUsed);
            return true;
        }
        return false;
    }
}

pragma solidity ^0.8.24;
interface IBlindAuction {
    enum Phase {
        Bidding,
        Reveal,
        AwaitingFinalization,
        Ended,
        Cancelled
    }
    struct Bid {
        bytes32 blindedBid;
        uint256 deposit;
    }
    event BidPlaced(address indexed bidder, uint256 bidIndex, uint256 deposit);
    event BidRevealed(address indexed bidder, uint256 bidIndex, uint256 value, bool valid);
    event HighestBidIncreased(address indexed bidder, uint256 amount);
    event RevealDeadlineExtended(uint256 newRevealEnd, uint256 extensionsUsed);
    event AuctionFinalized(address indexed winner, uint256 winningAmount, bool reserveMet);
    event AuctionCancelled(address indexed by, uint256 timestamp);
    event Withdrawn(address indexed bidder, uint256 amount);
    event CancelledRefund(address indexed bidder, uint256 amount);
    error InvalidPhase(Phase current, Phase required);
    error ZeroAddress();
    error InvalidTimes();
    error TooManyBids(uint256 max);
    error ArrayLengthMismatch();
    error NothingToWithdraw();
    error TransferFailed();
    error AlreadyFinalized();
    error DirectPaymentNotAllowed();
    function placeBid(bytes32 _blindedBid) external payable;
    function computeBlindedBid(uint256 _value, bool _fake, bytes32 _secret) external pure returns (bytes32);
    function reveal(uint256[] calldata _values, bool[] calldata _fakes, bytes32[] calldata _secrets) external;
    function finalizeAuction() external;
    function withdraw() external;
    function cancelAuction() external;
    function withdrawIfCancelled() external;
    function pause() external;
    function unpause() external;
    function currentPhase() external view returns (Phase);
    function timeUntilPhaseChange() external view returns (uint256);
    function beneficiary() external view returns (address payable);
    function reservePrice() external view returns (uint256);
    function biddingEnd() external view returns (uint256);
    function revealEnd() external view returns (uint256);
    function revealExtensionsUsed() external view returns (uint256);
    function auctionEnded() external view returns (bool);
    function auctionCancelled() external view returns (bool);
    function highestBidder() external view returns (address);
    function highestBid() external view returns (uint256);
    function getMyBidCount() external view returns (uint256);
    function getBidCount(address _bidder) external view returns (uint256);
    function getPendingReturn(address _bidder) external view returns (uint256);
}

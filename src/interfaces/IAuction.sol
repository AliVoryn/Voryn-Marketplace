// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IAuction {
    enum Phase {
        Created,
        Scheduled,
        Active,
        Ended,
        Finalizable,
        Finalized,
        Failed,
        Cancelled
    }

    struct Auction {
        uint256 id;
        address seller;
        address nft;
        uint256 tokenId;
        uint256 reservePrice;
        uint256 minIncrement;
        uint256 duration;
        uint64 startAt;
        uint64 endAt;
        uint64 extensionWindow;
        uint64 extensionTime;
        uint8 maxExtensions;
        uint8 extensionsUsed;
        Phase phase;
        address highestBidder;
        uint256 highestBid;
        uint256 winningAmount;
    }
    event AuctionCreated(
        uint256 indexed auctionId,
        address indexed seller,
        address indexed nft,
        uint256 tokenId,
        uint256 reservePrice,
        uint64 startAt,
        uint64 endAt
    );
    event AuctionStarted(uint256 indexed auctionId, uint64 startAt, uint64 endAt);
    event BidPlaced(uint256 indexed auctionId, address indexed bidder, uint256 amount);
    event AuctionExtended(uint256 indexed auctionId, uint64 newEndAt, uint8 extensionsUsed);
    event AuctionEnded(uint256 indexed auctionId);
    event AuctionFinalized(uint256 indexed auctionId, address indexed winner, uint256 amount, bool successful);
    event BidRefundCredited(address indexed bidder, uint256 indexed auctionId, uint256 amount);
    event AuctionCancelled(uint256 indexed auctionId);
    event BuyoutConfigured(uint256 indexed auctionId, uint256 buyoutPrice);
    event BuyoutExecuted(uint256 indexed auctionId, address indexed buyer, uint256 amount);
    event NFTEscrowed(uint256 indexed auctionId, address indexed seller, uint256 indexed tokenId);
    event NFTReleased(uint256 indexed auctionId, address indexed recipient, uint256 indexed tokenId);
    error ZeroAddress();
    error InvalidTreasury();
    error InvalidFeeBps();
    error InvalidTime();
    error InvalidPrice();
    error InvalidIncrement();
    error InvalidPhase();
    error AuctionNotFound();
    error BidTooLow();
    error NotSeller();
    error SellerCannotBid();
    error NotFinalizable();
    error SettlementFailed();
    error InvalidBuyout();
    error UnsupportedAsset();
    error EscrowInvariantBroken();
    error DirectPaymentNotAllowed();
    function createAuction(
        address nft,
        uint256 tokenId,
        uint256 reservePrice,
        uint256 minIncrement,
        uint64 startAt,
        uint64 duration
    ) external returns (uint256 auctionId);
    function startAuction(uint256 auctionId) external;
    function placeBid(uint256 auctionId) external payable;
    function configureBuyout(uint256 auctionId, uint256 price) external;
    function buyout(uint256 auctionId) external payable;
    function endAuction(uint256 auctionId) external;
    function cancelAuction(uint256 auctionId) external;
    function finalizeAuction(uint256 auctionId) external;
    function withdrawRefund() external;
    function getAuction(uint256 auctionId) external view returns (Auction memory);
}

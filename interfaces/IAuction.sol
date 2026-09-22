// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IAuction {
    enum Phase { Created, Scheduled, Active, Ended, Finalizable, Finalized, Failed, Cancelled }

    struct Auction {
        uint id;
        address seller;
        address nft;
        uint tokenId;
        uint reservePrice;
        uint minIncrement;
        uint duration;
        uint64 startAt;
        uint64 endAt;
        uint64 extensionWindow;
        uint64 extensionTime;
        uint8 maxExtensions;
        uint8 extensionsUsed;
        Phase phase;
        address highestBidder;
        uint highestBid;
        uint winningAmount;
    }

    event AuctionCreated(uint indexed auctionId, address indexed seller, address indexed nft, uint tokenId, uint reservePrice, uint64 startAt, uint64 endAt);
    event AuctionStarted(uint indexed auctionId, uint64 startAt, uint64 endAt);
    event BidPlaced(uint indexed auctionId, address indexed bidder, uint amount);
    event AuctionExtended(uint indexed auctionId, uint64 newEndAt, uint8 extensionsUsed);
    event AuctionEnded(uint indexed auctionId);
    event AuctionFinalized(uint indexed auctionId, address indexed winner, uint amount, bool successful);
    event BidRefundCredited(address indexed bidder, uint indexed auctionId, uint amount);
    event AuctionCancelled(uint indexed auctionId);
    event BuyoutConfigured(uint indexed auctionId, uint buyoutPrice);
    event BuyoutExecuted(uint indexed auctionId, address indexed buyer, uint amount);
    event NFTEscrowed(uint indexed auctionId, address indexed seller, uint indexed tokenId);
    event NFTReleased(uint indexed auctionId, address indexed recipient, uint indexed tokenId);

    error ZeroAddress();
    error InvalidTreasury();
    error InvalidFeeBps();
    error InvalidTime();
    error InvalidPrice();
    error InvalidIncrement();
    error InvalidPhase();
    error BidTooLow();
    error NotSeller();
    error NotFinalizable();
    error SettlementFailed();
    error InvalidBuyout();
    error EscrowInvariantBroken();
    error DirectPaymentNotAllowed();

    function createAuction(address nft, uint tokenId, uint reservePrice, uint minIncrement, uint64 startAt, uint64 duration) external returns (uint auctionId);
    function startAuction(uint auctionId) external;
    function placeBid(uint auctionId) external payable;
    function configureBuyout(uint auctionId, uint price) external;
    function buyout(uint auctionId) external payable;
    function endAuction(uint auctionId) external;
    function cancelAuction(uint auctionId) external;
    function finalizeAuction(uint auctionId) external;
    function withdrawRefund() external;
    function getAuction(uint auctionId) external view returns (Auction memory);
}

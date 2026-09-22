// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IDutchAuction {
    enum AuctionStatus {
        Created,
        Active,
        Sold,
        Cancelled,
        Expired
    }

    struct Auction {
        uint256 id;
        address seller;
        address nft;
        uint256 tokenId;
        uint256 startPrice;
        uint256 endPrice;
        uint64 startAt;
        uint64 endAt;
        AuctionStatus status;
        address buyer;
        uint256 soldPrice;
    }

    event DutchAuctionCreated(
        uint256 indexed auctionId,
        address indexed seller,
        address indexed nft,
        uint256 tokenId,
        uint256 startPrice,
        uint256 endPrice,
        uint64 startAt,
        uint64 endAt
    );
    event DutchAuctionStarted(uint256 indexed auctionId, uint64 startAt, uint64 endAt);
    event DutchAuctionPurchased(uint256 indexed auctionId, address indexed buyer, uint256 price);
    event DutchAuctionCancelled(uint256 indexed auctionId);
    event DutchAuctionExpired(uint256 indexed auctionId);
    event DutchAuctionFeePaid(uint256 indexed auctionId, uint256 amount);

    error ZeroAddress();
    error InvalidPriceRange();
    error InvalidTime();
    error InvalidPhase();
    error NotSeller();
    error InvalidAuction();
    error PaymentMismatch();
    error FeeTooHigh();
    error SellerNoLongerOwnsAsset();
    error DirectPaymentNotAllowed();

    function createAuction(
        address nft,
        uint256 tokenId,
        uint256 startPrice,
        uint256 endPrice,
        uint64 startAt,
        uint64 duration
    ) external returns (uint256 auctionId);

    function buy(uint256 auctionId) external payable;
    function cancelAuction(uint256 auctionId) external;
    function expireAuction(uint256 auctionId) external;
    function currentPrice(uint256 auctionId) external view returns (uint256);
    function getAuction(uint256 auctionId) external view returns (Auction memory);
    function auctionCount() external view returns (uint256);
}

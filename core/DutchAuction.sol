// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

import "../interfaces/ICustomNFT.sol";
import "../interfaces/IDutchAuction.sol";
import "../interfaces/ITreasury.sol";
import "../libraries/FeeMath.sol";

contract DutchAuction is Ownable2Step, ReentrancyGuard, Pausable, IDutchAuction {
    using Math for uint256;

    uint16 public immutable protocolFeeBps;
    address public immutable treasury;

    uint256 public nextAuctionId = 1;
    mapping(uint256 => Auction) private auctions;


    constructor(address initialOwner, address treasury_, uint16 feeBps) Ownable(initialOwner) {
        if (treasury_ == address(0)) revert ZeroAddress();
        if (feeBps > 1000) revert FeeTooHigh();

        treasury = treasury_;
        protocolFeeBps = feeBps;
    }
 
    function createAuction(
        address nft,
        uint256 tokenId,
        uint256 startPrice,
        uint256 endPrice,
        uint64 startAt,
        uint64 duration
    ) external override nonReentrant whenNotPaused returns (uint256 auctionId) {
        if (nft == address(0)) revert ZeroAddress();
        if (startPrice == 0 || endPrice == 0 || endPrice >= startPrice) {
            revert InvalidPriceRange();
        }
        if (duration == 0) revert InvalidTime();
        if (startAt != 0 && startAt < block.timestamp) revert InvalidTime();
        if (ICustomNFT(nft).ownerOf(tokenId) != msg.sender) revert NotSeller();

        uint64 effectiveStart = startAt == 0 ? uint64(block.timestamp) : startAt;
        uint64 effectiveEnd = effectiveStart + duration;
        if (effectiveEnd <= effectiveStart) revert InvalidTime();

        auctionId = nextAuctionId++;

        Auction storage auction = auctions[auctionId];
        auction.id = auctionId;
        auction.seller = msg.sender;
        auction.nft = nft;
        auction.tokenId = tokenId;
        auction.startPrice = startPrice;
        auction.endPrice = endPrice;
        auction.startAt = effectiveStart;
        auction.endAt = effectiveEnd;
        auction.status = effectiveStart > block.timestamp
            ? AuctionStatus.Created
            : AuctionStatus.Active;
 
        ICustomNFT(nft).transferFrom(msg.sender, address(this), tokenId);

        emit DutchAuctionCreated(
            auctionId,
            msg.sender,
            nft,
            tokenId,
            startPrice,
            endPrice,
            effectiveStart,
            effectiveEnd
        );

        if (auction.status == AuctionStatus.Active) {
            emit DutchAuctionStarted(auctionId, effectiveStart, effectiveEnd);
        }
    }
 
    function buy(uint256 auctionId) external payable override nonReentrant whenNotPaused {
        Auction storage auction = auctions[auctionId];
        if (auction.seller == address(0)) revert InvalidAuction();

        _activateIfReady(auction);

        if (auction.status != AuctionStatus.Active) revert InvalidPhase();
        if (block.timestamp >= auction.endAt) revert InvalidPhase();

        uint256 current = _currentPrice(auction);
        if (msg.value != current) revert PaymentMismatch();

        if (ICustomNFT(auction.nft).ownerOf(auction.tokenId) != address(this)) {
            revert SellerNoLongerOwnsAsset();
        }

        (uint256 fee, uint256 sellerAmount) = FeeMath.split(msg.value, protocolFeeBps);

        auction.status = AuctionStatus.Sold;
        auction.buyer = msg.sender;
        auction.soldPrice = msg.value;

        if (fee > 0) {
            ITreasury(treasury).credit{value: fee}(
                ITreasury(treasury).feeRecipientForProtocol(),
                keccak256("DUTCH_AUCTION_FEE")
            );
            emit DutchAuctionFeePaid(auctionId, fee);
        }

        ITreasury(treasury).credit{value: sellerAmount}(
            auction.seller,
            keccak256("DUTCH_AUCTION_PROCEEDS")
        );

        ICustomNFT(auction.nft).transferFrom(address(this), msg.sender, auction.tokenId);

        emit DutchAuctionPurchased(auctionId, msg.sender, msg.value);
    }

 
    function cancelAuction(uint256 auctionId) external override nonReentrant whenNotPaused {
        Auction storage auction = auctions[auctionId];
        if (auction.seller == address(0)) revert InvalidAuction();
        if (msg.sender != auction.seller && msg.sender != owner()) revert NotSeller();
        if (
            auction.status != AuctionStatus.Created &&
            auction.status != AuctionStatus.Active
        ) revert InvalidPhase();
        if (block.timestamp >= auction.endAt) revert InvalidPhase();

        auction.status = AuctionStatus.Cancelled;
        ICustomNFT(auction.nft).transferFrom(address(this), auction.seller, auction.tokenId);

        emit DutchAuctionCancelled(auctionId);
    }

     function expireAuction(uint256 auctionId) external override nonReentrant whenNotPaused {
        Auction storage auction = auctions[auctionId];
        if (auction.seller == address(0)) revert InvalidAuction();
        if (
            auction.status != AuctionStatus.Created &&
            auction.status != AuctionStatus.Active
        ) revert InvalidPhase();
        if (block.timestamp < auction.endAt) revert InvalidTime();

        auction.status = AuctionStatus.Expired;
        ICustomNFT(auction.nft).transferFrom(address(this), auction.seller, auction.tokenId);

        emit DutchAuctionExpired(auctionId);
    }
 
    function currentPrice(uint256 auctionId) external view override returns (uint256) {
        Auction memory auction = auctions[auctionId];
        if (auction.seller == address(0)) revert InvalidAuction();
        return _currentPrice(auction);
    }

    function getAuction(uint256 auctionId) external view override returns (Auction memory) {
        Auction memory auction = auctions[auctionId];
        if (auction.seller == address(0)) revert InvalidAuction();
        return auction;
    }

    function auctionCount() external view override returns (uint256) {
        return nextAuctionId - 1;
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function _activateIfReady(Auction storage auction) internal {
        if (auction.status == AuctionStatus.Created && block.timestamp >= auction.startAt) {
            auction.status = AuctionStatus.Active;
            emit DutchAuctionStarted(auction.id, auction.startAt, auction.endAt);
        }
    }

    function _currentPrice(Auction memory auction) internal view returns (uint256) {
        if (block.timestamp <= auction.startAt) return auction.startPrice;
        if (block.timestamp >= auction.endAt) return auction.endPrice;

        uint256 elapsed = block.timestamp - auction.startAt;
        uint256 duration = auction.endAt - auction.startAt;
        uint256 priceDrop = auction.startPrice - auction.endPrice;
        uint256 reduction = Math.mulDiv(priceDrop, elapsed, duration);

        return auction.startPrice - reduction;
    }

    receive() external payable {
        revert DirectPaymentNotAllowed();
    }
}

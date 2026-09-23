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
import "../libraries/AutomationScanLib.sol";

contract DutchAuction is Ownable2Step, ReentrancyGuard, Pausable, IDutchAuction {
    using Math for uint256;
    uint16 public immutable protocolFeeBps;
    address public immutable treasury;
    uint256 public nextAuctionId = 1;
    mapping(uint256 => Auction) private auctions;

    constructor(address initialOwner, address treasury_, uint16 feeBps) Ownable(initialOwner) {
        if (treasury_ == address(0)) revert ZeroAddress();
        if (treasury_.code.length == 0) revert ZeroAddress();
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
        if (nft.code.length == 0) revert ZeroAddress();
        if (startPrice == 0 || endPrice == 0 || endPrice >= startPrice) {
            revert InvalidPriceRange();
        }
        if (duration == 0) revert InvalidTime();
        if (startAt != 0 && startAt < block.timestamp) revert InvalidTime();
        if (ICustomNFT(nft).ownerOf(tokenId) != msg.sender) revert NotSeller();
        uint64 effectiveStart = startAt == 0 ? uint64(block.timestamp) : startAt;
        if (uint256(effectiveStart) > type(uint64).max - duration) revert InvalidTime();
        uint64 effectiveEnd = effectiveStart + duration;
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
        auction.status = effectiveStart > block.timestamp ? AuctionStatus.Created : AuctionStatus.Active;
        ICustomNFT(nft).transferFrom(msg.sender, address(this), tokenId);
        emit DutchAuctionCreated(
            auctionId, msg.sender, nft, tokenId, startPrice, endPrice, effectiveStart, effectiveEnd
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
        if (msg.sender == auction.seller) revert NotSeller();
        if (block.timestamp >= auction.endAt) revert InvalidPhase();
        uint256 current = _currentPrice(auction);
        if (msg.value < current) revert PaymentMismatch();
        if (ICustomNFT(auction.nft).ownerOf(auction.tokenId) != address(this)) {
            revert SellerNoLongerOwnsAsset();
        }
        (uint256 fee, uint256 sellerAmount) = FeeMath.split(current, protocolFeeBps);
        auction.status = AuctionStatus.Sold;
        auction.buyer = msg.sender;
        auction.soldPrice = current;
        if (fee > 0) {
            ITreasury(treasury).credit{ value: fee }(
                ITreasury(treasury).feeRecipientForProtocol(), keccak256("DUTCH_AUCTION_FEE")
            );
            emit DutchAuctionFeePaid(auctionId, fee);
        }
        ITreasury(treasury).credit{ value: sellerAmount }(auction.seller, keccak256("DUTCH_AUCTION_PROCEEDS"));
        ICustomNFT(auction.nft).transferFrom(address(this), msg.sender, auction.tokenId);
        emit DutchAuctionPurchased(auctionId, msg.sender, current);
        uint256 excess = msg.value - current;
        if (excess > 0) {
            (bool refunded,) = payable(msg.sender).call{ value: excess }("");
            if (!refunded) revert RefundFailed();
        }
    }

    function cancelAuction(uint256 auctionId) external override nonReentrant whenNotPaused {
        Auction storage auction = auctions[auctionId];
        if (auction.seller == address(0)) revert InvalidAuction();
        if (msg.sender != auction.seller && msg.sender != owner()) revert NotSeller();
        if (auction.status != AuctionStatus.Created && auction.status != AuctionStatus.Active) revert InvalidPhase();
        if (block.timestamp >= auction.endAt) revert InvalidPhase();
        auction.status = AuctionStatus.Cancelled;
        ICustomNFT(auction.nft).transferFrom(address(this), auction.seller, auction.tokenId);
        emit DutchAuctionCancelled(auctionId);
    }

    function expireAuction(uint256 auctionId) external override nonReentrant whenNotPaused {
        Auction storage auction = auctions[auctionId];
        if (auction.seller == address(0)) revert InvalidAuction();
        if (auction.status != AuctionStatus.Created && auction.status != AuctionStatus.Active) revert InvalidPhase();
        if (block.timestamp < auction.endAt) revert InvalidTime();
        auction.status = AuctionStatus.Expired;
        ICustomNFT(auction.nft).transferFrom(address(this), auction.seller, auction.tokenId);
        emit DutchAuctionExpired(auctionId);
    }

    function automationDueIds(uint256 cycle, uint256 maxScan, uint256 maxItems)
        external
        view
        returns (uint256[] memory dueIds)
    {
        if (maxItems == 0 || maxScan == 0 || paused()) return new uint256[](0);
        (uint256 startId, uint256 endId) = AutomationScanLib.window(nextAuctionId - 1, cycle, maxScan);
        uint256 capacity = AutomationScanLib.capacity(maxItems, startId, endId);
        dueIds = new uint256[](capacity);
        uint256 found;
        for (uint256 id = startId; id < endId && found < capacity; ++id) {
            Auction storage auction = auctions[id];
            if (auction.seller == address(0)) continue;
            if (
                (auction.status == AuctionStatus.Created || auction.status == AuctionStatus.Active)
                    && auction.endAt != 0 && block.timestamp >= auction.endAt
            ) {
                dueIds[found++] = id;
            }
        }
        assembly {
            mstore(dueIds, found)
        }
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

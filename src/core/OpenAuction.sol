// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "../interfaces/IAuction.sol";
import "../interfaces/ICustomNFT.sol";
import "../interfaces/ITreasury.sol";
import "../libraries/AuctionMath.sol";
import "../libraries/FeeMath.sol";
import "../libraries/PhaseLogic.sol";
import "../libraries/AutomationScanLib.sol";

contract OpenAuction is Ownable2Step, ReentrancyGuard, Pausable, IAuction {
    struct BidSnapshot {
        address bidder;
        uint256 amount;
        uint64 timestamp;
    }
    address public immutable treasury;
    uint16 public immutable protocolFeeBps;
    uint256 public nextAuctionId = 1;
    uint256 public totalActiveBidLiability;
    uint256 public totalRefundLiability;
    mapping(uint256 => Auction) private auctions;
    mapping(address => uint256) private refunds;
    mapping(uint256 => BidSnapshot[]) private history;
    mapping(uint256 => bool) public buyoutEnabled;
    mapping(uint256 => uint256) public buyoutPrice;
    event RefundWithdrawn(address indexed bidder, uint256 amount);
    event AuctionFeePaid(uint256 indexed auctionId, uint256 amount);

    constructor(address initialOwner, address treasury_, uint16 feeBps) Ownable(initialOwner) {
        if (treasury_ == address(0) || treasury_.code.length == 0) revert InvalidTreasury();
        if (feeBps > 1000) revert InvalidFeeBps();
        treasury = treasury_;
        protocolFeeBps = feeBps;
    }
    modifier sellerOrOwner(uint256 auctionId) {
        address auctionSeller = auctions[auctionId].seller;
        if (auctionSeller == address(0)) revert AuctionNotFound();
        if (msg.sender != auctionSeller && msg.sender != owner()) revert NotSeller();
        _;
    }

    function createAuction(
        address nft,
        uint256 tokenId,
        uint256 reservePrice,
        uint256 minIncrement,
        uint64 startAt,
        uint64 duration
    ) external override nonReentrant whenNotPaused returns (uint256 auctionId) {
        if (nft == address(0)) revert ZeroAddress();
        if (nft.code.length == 0) revert UnsupportedAsset();
        if (reservePrice == 0) revert InvalidPrice();
        if (minIncrement == 0) revert InvalidIncrement();
        if (duration == 0) revert InvalidTime();
        if (startAt != 0 && startAt < block.timestamp) revert InvalidTime();
        uint64 effectiveStart = startAt == 0 ? uint64(block.timestamp) : startAt;
        if (uint256(effectiveStart) > type(uint64).max - duration) revert InvalidTime();
        if (ICustomNFT(nft).ownerOf(tokenId) != msg.sender) revert NotSeller();
        auctionId = nextAuctionId++;
        Auction storage a = auctions[auctionId];
        a.id = auctionId;
        a.seller = msg.sender;
        a.nft = nft;
        a.tokenId = tokenId;
        a.reservePrice = reservePrice;
        a.minIncrement = minIncrement;
        a.duration = duration;
        a.startAt = effectiveStart;
        a.endAt = effectiveStart + duration;
        a.extensionWindow = 5 minutes;
        a.extensionTime = 5 minutes;
        a.maxExtensions = 3;
        a.phase = startAt != 0 && startAt > block.timestamp ? Phase.Scheduled : Phase.Created;
        ICustomNFT(nft).transferFrom(msg.sender, address(this), tokenId);
        emit AuctionCreated(auctionId, msg.sender, nft, tokenId, reservePrice, a.startAt, a.endAt);
        emit NFTEscrowed(auctionId, msg.sender, tokenId);
    }

    function startAuction(uint256 auctionId) external override whenNotPaused {
        Auction storage a = _existing(auctionId);
        if (a.phase != Phase.Created && a.phase != Phase.Scheduled) revert InvalidPhase();
        if (a.seller != msg.sender) revert NotSeller();
        if (block.timestamp < a.startAt) revert InvalidTime();
        if (block.timestamp >= a.endAt) revert InvalidPhase();
        a.phase = Phase.Active;
        emit AuctionStarted(auctionId, a.startAt, a.endAt);
    }

    function configureBuyout(uint256 auctionId, uint256 price) external override sellerOrOwner(auctionId) {
        Auction storage a = auctions[auctionId];
        _activateIfReady(a);
        if (a.phase != Phase.Created && a.phase != Phase.Scheduled && a.phase != Phase.Active) revert InvalidPhase();
        if (block.timestamp >= a.endAt) revert InvalidPhase();
        if (price <= a.reservePrice) revert InvalidBuyout();
        buyoutEnabled[auctionId] = true;
        buyoutPrice[auctionId] = price;
        emit BuyoutConfigured(auctionId, price);
    }

    function placeBid(uint256 auctionId) external payable override nonReentrant whenNotPaused {
        Auction storage a = _existing(auctionId);
        _activateIfReady(a);
        if (a.phase != Phase.Active) revert InvalidPhase();
        if (msg.sender == a.seller) revert SellerCannotBid();
        if (block.timestamp >= a.endAt) revert InvalidPhase();
        uint256 minimum = a.highestBid == 0 ? a.reservePrice : AuctionMath.nextMinimumBid(a.highestBid, a.minIncrement);
        if (msg.value < minimum) revert BidTooLow();
        if (a.highestBidder != address(0)) {
            totalActiveBidLiability -= a.highestBid;
            _creditRefund(a.highestBidder, a.highestBid, auctionId);
        }
        a.highestBidder = msg.sender;
        a.highestBid = msg.value;
        totalActiveBidLiability += msg.value;
        history[auctionId].push(BidSnapshot(msg.sender, msg.value, uint64(block.timestamp)));
        if (AuctionMath.shouldExtend(
                uint64(block.timestamp), a.endAt, a.extensionWindow, a.extensionsUsed, a.maxExtensions
            )) {
            if (uint256(a.endAt) > type(uint64).max - a.extensionTime) revert InvalidTime();
            a.endAt += a.extensionTime;
            a.extensionsUsed += 1;
            emit AuctionExtended(auctionId, a.endAt, a.extensionsUsed);
        }
        emit BidPlaced(auctionId, msg.sender, msg.value);
        _assertEscrowInvariant();
    }

    function buyout(uint256 auctionId) external payable override nonReentrant whenNotPaused {
        Auction storage a = _existing(auctionId);
        _activateIfReady(a);
        if (a.phase != Phase.Active) revert InvalidPhase();
        if (!buyoutEnabled[auctionId]) revert InvalidBuyout();
        if (block.timestamp >= a.endAt) revert InvalidPhase();
        if (msg.value != buyoutPrice[auctionId]) revert BidTooLow();
        if (msg.sender == a.seller) revert NotSeller();
        if (buyoutPrice[auctionId] <= a.highestBid) revert InvalidBuyout();
        if (a.highestBidder != address(0)) {
            _creditRefund(a.highestBidder, a.highestBid, auctionId);
            totalActiveBidLiability -= a.highestBid;
        }
        a.highestBidder = msg.sender;
        a.winningAmount = msg.value;
        a.highestBid = 0;
        a.phase = Phase.Finalized;
        ICustomNFT(a.nft).transferFrom(address(this), msg.sender, a.tokenId);
        emit NFTReleased(auctionId, msg.sender, a.tokenId);
        _settleSeller(auctionId, a.seller, msg.value);
        emit BuyoutExecuted(auctionId, msg.sender, msg.value);
        emit AuctionFinalized(auctionId, msg.sender, msg.value, true);
        _assertEscrowInvariant();
    }

    function endAuction(uint256 auctionId) external override whenNotPaused {
        Auction storage a = _existing(auctionId);
        _activateIfReady(a);
        if (a.phase != Phase.Active) revert InvalidPhase();
        if (!PhaseLogic.afterEnd(uint64(block.timestamp), a.endAt)) revert NotFinalizable();
        a.phase = Phase.Ended;
        emit AuctionEnded(auctionId);
    }

    function cancelAuction(uint256 auctionId) external override sellerOrOwner(auctionId) nonReentrant {
        Auction storage a = auctions[auctionId];
        if (a.phase != Phase.Created && a.phase != Phase.Scheduled && a.phase != Phase.Active) revert InvalidPhase();
        if (block.timestamp >= a.endAt) revert InvalidPhase();
        a.phase = Phase.Cancelled;
        if (a.highestBidder != address(0) && a.highestBid > 0) {
            _creditRefund(a.highestBidder, a.highestBid, auctionId);
            totalActiveBidLiability -= a.highestBid;
        }
        a.highestBid = 0;
        a.highestBidder = address(0);
        ICustomNFT(a.nft).transferFrom(address(this), a.seller, a.tokenId);
        emit NFTReleased(auctionId, a.seller, a.tokenId);
        emit AuctionCancelled(auctionId);
        _assertEscrowInvariant();
    }

    function finalizeAuction(uint256 auctionId) external override nonReentrant whenNotPaused {
        Auction storage a = _existing(auctionId);
        _activateIfReady(a);
        if (a.phase == Phase.Active) {
            if (!PhaseLogic.afterEnd(uint64(block.timestamp), a.endAt)) revert NotFinalizable();
            a.phase = Phase.Ended;
            emit AuctionEnded(auctionId);
        }
        if (a.phase != Phase.Ended) revert NotFinalizable();
        bool successful = a.highestBidder != address(0) && a.highestBid >= a.reservePrice;
        if (successful) {
            address winner = a.highestBidder;
            uint256 amount = a.highestBid;
            a.winningAmount = amount;
            a.highestBid = 0;
            totalActiveBidLiability -= amount;
            a.phase = Phase.Finalized;
            ICustomNFT(a.nft).transferFrom(address(this), winner, a.tokenId);
            emit NFTReleased(auctionId, winner, a.tokenId);
            _settleSeller(auctionId, a.seller, amount);
            emit AuctionFinalized(auctionId, winner, amount, true);
        } else {
            if (a.highestBidder != address(0) && a.highestBid > 0) {
                _creditRefund(a.highestBidder, a.highestBid, auctionId);
                totalActiveBidLiability -= a.highestBid;
            }
            a.highestBid = 0;
            a.highestBidder = address(0);
            a.phase = Phase.Failed;
            ICustomNFT(a.nft).transferFrom(address(this), a.seller, a.tokenId);
            emit NFTReleased(auctionId, a.seller, a.tokenId);
            emit AuctionFinalized(auctionId, address(0), 0, false);
        }
        _assertEscrowInvariant();
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
                (auction.phase == Phase.Created
                        || auction.phase == Phase.Scheduled
                        || auction.phase == Phase.Active
                        || auction.phase == Phase.Ended
                        || auction.phase == Phase.Finalizable) && auction.endAt != 0 && block.timestamp >= auction.endAt
            ) {
                dueIds[found++] = id;
            }
        }
        assembly {
            mstore(dueIds, found)
        }
    }

    function withdrawRefund() external override nonReentrant {
        uint256 amount = refunds[msg.sender];
        if (amount == 0) revert SettlementFailed();
        refunds[msg.sender] = 0;
        totalRefundLiability -= amount;
        (bool success,) = payable(msg.sender).call{ value: amount }("");
        if (!success) revert SettlementFailed();
        emit RefundWithdrawn(msg.sender, amount);
    }

    function getAuction(uint256 auctionId) external view override returns (Auction memory) {
        return auctions[auctionId];
    }

    function getRefund(address account) external view returns (uint256) {
        return refunds[account];
    }

    function bidHistoryLength(uint256 auctionId) external view returns (uint256) {
        return history[auctionId].length;
    }

    function bidHistoryAt(uint256 auctionId, uint256 index) external view returns (BidSnapshot memory) {
        return history[auctionId][index];
    }

    function escrowedBalance() external view returns (uint256) {
        return address(this).balance;
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function _existing(uint256 auctionId) internal view returns (Auction storage a) {
        a = auctions[auctionId];
        if (a.seller == address(0)) revert AuctionNotFound();
    }

    function _activateIfReady(Auction storage a) internal {
        if ((a.phase == Phase.Created || a.phase == Phase.Scheduled) && block.timestamp >= a.startAt) {
            a.phase = Phase.Active;
            emit AuctionStarted(a.id, a.startAt, a.endAt);
        }
    }

    function _creditRefund(address bidder, uint256 amount, uint256 auctionId) internal {
        if (amount == 0) return;
        refunds[bidder] += amount;
        totalRefundLiability += amount;
        emit BidRefundCredited(bidder, auctionId, amount);
    }

    function _settleSeller(uint256 auctionId, address seller, uint256 amount) internal {
        (uint256 fee, uint256 sellerAmount) = FeeMath.split(amount, protocolFeeBps);
        if (fee > 0) {
            ITreasury(treasury).credit{ value: fee }(
                ITreasury(treasury).feeRecipientForProtocol(), keccak256("AUCTION_FEE")
            );
        }
        ITreasury(treasury).credit{ value: sellerAmount }(seller, keccak256("AUCTION_PROCEEDS"));
        emit AuctionFeePaid(auctionId, fee);
    }

    function _assertEscrowInvariant() internal view {
        uint256 expected = totalActiveBidLiability + totalRefundLiability;
        if (address(this).balance < expected) revert EscrowInvariantBroken();
    }

    receive() external payable {
        revert DirectPaymentNotAllowed();
    }
}

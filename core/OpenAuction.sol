// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/Address.sol";

import "../interfaces/IAuction.sol";
import "../interfaces/ICustomNFT.sol";
import "../interfaces/ITreasury.sol";
import "../libraries/AuctionMath.sol";
import "../libraries/FeeMath.sol";
import "../libraries/PhaseLogic.sol";

contract OpenAuction is Ownable2Step, ReentrancyGuard, Pausable, IAuction {
    using Address for address payable;

    struct BidSnapshot { address bidder; uint amount; uint64 timestamp; }

    address public immutable treasury;
    uint16 public immutable protocolFeeBps;

    uint public nextAuctionId = 1;
    uint public totalActiveBidLiability;
    uint public totalRefundLiability;

    mapping(uint => Auction) private auctions;
    mapping(address => uint) private refunds;
    mapping(uint => BidSnapshot[]) private history;
    mapping(uint => bool) public buyoutEnabled;
    mapping(uint => uint) public buyoutPrice;

    event RefundWithdrawn(address indexed bidder, uint amount);
    event AuctionFeePaid(uint indexed auctionId, uint amount);

    constructor(address initialOwner, address treasury_, uint16 feeBps) Ownable(initialOwner) {
        if (treasury_ == address(0)) revert InvalidTreasury();
        if (feeBps > 1000) revert InvalidFeeBps();
        treasury = treasury_;
        protocolFeeBps = feeBps;
    }

    modifier sellerOrOwner(uint auctionId) {
        Auction memory auction = auctions[auctionId];
        if (msg.sender != auction.seller && msg.sender != owner()) revert NotSeller();
        _;
    }

    function createAuction(address nft, uint tokenId, uint reservePrice, uint minIncrement, uint64 startAt, uint64 duration)
        external override nonReentrant whenNotPaused returns (uint auctionId)
    {
        if (nft == address(0)) revert ZeroAddress();
        if (reservePrice == 0) revert InvalidPrice();
        if (minIncrement == 0) revert InvalidIncrement();
        if (duration == 0) revert InvalidTime();
        if (startAt != 0 && startAt < block.timestamp) revert InvalidTime();
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
        a.startAt = startAt == 0 ? uint64(block.timestamp) : startAt;
        a.endAt = a.startAt + duration;
        a.extensionWindow = 5 minutes;
        a.extensionTime = 5 minutes;
        a.maxExtensions = 3;
        a.phase = startAt != 0 && startAt > block.timestamp ? Phase.Scheduled : Phase.Created;

         ICustomNFT(nft).transferFrom(msg.sender, address(this), tokenId);

        emit AuctionCreated(auctionId, msg.sender, nft, tokenId, reservePrice, a.startAt, a.endAt);
        emit NFTEscrowed(auctionId, msg.sender, tokenId);
    }

    function startAuction(uint auctionId) external override whenNotPaused {
        Auction storage a = auctions[auctionId];
        if (a.phase != Phase.Created && a.phase != Phase.Scheduled) revert InvalidPhase();
        if (a.seller != msg.sender) revert NotSeller();
        if (block.timestamp < a.startAt) revert InvalidTime();
        if (block.timestamp >= a.endAt) revert InvalidPhase();
        a.phase = Phase.Active;
        emit AuctionStarted(auctionId, a.startAt, a.endAt);
    }

    function configureBuyout(uint auctionId, uint price) external override sellerOrOwner(auctionId) {
        Auction storage a = auctions[auctionId];
        if (a.phase != Phase.Active) revert InvalidPhase();
        if (block.timestamp >= a.endAt) revert InvalidPhase();
        if (price <= a.reservePrice) revert InvalidBuyout();
        buyoutEnabled[auctionId] = true;
        buyoutPrice[auctionId] = price;
        emit BuyoutConfigured(auctionId, price);
    }

    function placeBid(uint auctionId) external payable override nonReentrant whenNotPaused {
        Auction storage a = auctions[auctionId];
        _activateIfReady(a);
        if (a.phase != Phase.Active) revert InvalidPhase();
        if (block.timestamp >= a.endAt) revert InvalidPhase();

        uint minimum = a.highestBid == 0 ? a.reservePrice : AuctionMath.nextMinimumBid(a.highestBid, a.minIncrement);
        if (msg.value < minimum) revert BidTooLow();

        if (a.highestBidder != address(0)) {
            totalActiveBidLiability -= a.highestBid;
            _creditRefund(a.highestBidder, a.highestBid, auctionId);
        }
        a.highestBidder = msg.sender;
        a.highestBid = msg.value;
        totalActiveBidLiability += msg.value;

        history[auctionId].push(BidSnapshot(msg.sender, msg.value, uint64(block.timestamp)));

        if (AuctionMath.shouldExtend(uint64(block.timestamp), a.endAt, a.extensionWindow, a.extensionsUsed, a.maxExtensions)) {
            a.endAt += a.extensionTime;
            a.extensionsUsed += 1;
            emit AuctionExtended(auctionId, a.endAt, a.extensionsUsed);
        }

        emit BidPlaced(auctionId, msg.sender, msg.value);
        _assertEscrowInvariant();
    }

    function buyout(uint auctionId) external payable override nonReentrant whenNotPaused {
        Auction storage a = auctions[auctionId];
        _activateIfReady(a);
        if (a.phase != Phase.Active) revert InvalidPhase();
        if (!buyoutEnabled[auctionId]) revert InvalidBuyout();
        if (block.timestamp >= a.endAt) revert InvalidPhase();
        if (msg.value != buyoutPrice[auctionId]) revert BidTooLow();

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

    function endAuction(uint auctionId) external override whenNotPaused {
        Auction storage a = auctions[auctionId];
        _activateIfReady(a);
        if (a.phase != Phase.Active) revert InvalidPhase();
        if (!PhaseLogic.afterEnd(uint64(block.timestamp), a.endAt)) revert NotFinalizable();
        a.phase = Phase.Ended;
        emit AuctionEnded(auctionId);
    }

    function cancelAuction(uint auctionId) external override sellerOrOwner(auctionId) nonReentrant {
        Auction storage a = auctions[auctionId];
        if (a.phase != Phase.Created && a.phase != Phase.Scheduled && a.phase != Phase.Active && a.phase != Phase.Ended) revert InvalidPhase();
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

    function finalizeAuction(uint auctionId) external override nonReentrant whenNotPaused {
        Auction storage a = auctions[auctionId];

        _activateIfReady(a);

        if ((a.phase == Phase.Created || a.phase == Phase.Scheduled) && block.timestamp >= a.endAt) {
            a.phase = Phase.Ended;
            emit AuctionEnded(auctionId);
        }

        if (a.phase == Phase.Active) {
            if (!PhaseLogic.afterEnd(uint64(block.timestamp), a.endAt)) revert NotFinalizable();
            a.phase = Phase.Ended;
            emit AuctionEnded(auctionId);
        }

        if (a.phase != Phase.Ended && a.phase != Phase.Finalizable) revert NotFinalizable();
        if (block.timestamp < a.endAt) revert NotFinalizable();

        a.phase = Phase.Finalizable;
        bool successful = a.highestBidder != address(0) && a.highestBid >= a.reservePrice;

        if (successful) {
            address winner = a.highestBidder;
            uint amount = a.highestBid;

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

    function withdrawRefund() external override nonReentrant {
        uint amount = refunds[msg.sender];
        if (amount == 0) revert SettlementFailed();
        refunds[msg.sender] = 0;
        totalRefundLiability -= amount;
        (bool success,) = payable(msg.sender).call{value: amount}("");
        if (!success) revert SettlementFailed();
        emit RefundWithdrawn(msg.sender, amount);
    }

    function getAuction(uint auctionId) external view override returns (Auction memory) { return auctions[auctionId]; }
    
    function getRefund(address account) external view returns (uint) { return refunds[account]; }
    
    function bidHistoryLength(uint auctionId) external view returns (uint) { return history[auctionId].length; }
    
    function bidHistoryAt(uint auctionId, uint index) external view returns (BidSnapshot memory) { return history[auctionId][index]; }
    
    function escrowedBalance() external view returns (uint) { return address(this).balance; }

    function pause() external onlyOwner { _pause(); }
    function unpause() external onlyOwner { _unpause(); }

    function _activateIfReady(Auction storage a) internal {
        if ((a.phase == Phase.Created || a.phase == Phase.Scheduled) && block.timestamp >= a.startAt) {
            a.phase = Phase.Active;
            emit AuctionStarted(a.id, a.startAt, a.endAt);
        }
    }

    function _creditRefund(address bidder, uint amount, uint auctionId) internal {
        if (amount == 0) return;
        refunds[bidder] += amount;
        totalRefundLiability += amount;
        emit BidRefundCredited(bidder, auctionId, amount);
    }

    function _settleSeller(uint auctionId, address seller, uint amount) internal {
        (uint fee, uint sellerAmount) = FeeMath.split(amount, protocolFeeBps);

        if (fee > 0) {
            ITreasury(treasury).credit{value: fee}(
                ITreasury(treasury).feeRecipientForProtocol(),
                keccak256("AUCTION_FEE")
            );
        }

        ITreasury(treasury).credit{value: sellerAmount}(
            seller,
            keccak256("AUCTION_PROCEEDS")
        );

        emit AuctionFeePaid(auctionId, fee);
    }

    function _assertEscrowInvariant() internal view {
        uint expected = totalActiveBidLiability + totalRefundLiability;
        if (address(this).balance < expected) revert EscrowInvariantBroken();
    }

    receive() external payable { revert DirectPaymentNotAllowed(); }
}

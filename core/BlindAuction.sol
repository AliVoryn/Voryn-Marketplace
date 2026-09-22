// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import "../interfaces/IBlindAuction.sol";
import "../interfaces/ICustomNFT.sol";
import "../interfaces/ITreasury.sol";
import "../libraries/AuctionPhaseLib.sol";
import "../libraries/FeeMath.sol";

 
contract BlindAuction is IBlindAuction, Ownable2Step, Pausable, ReentrancyGuard {
    using AuctionPhaseLib for AuctionPhaseLib.Clock;
 
    address payable public immutable override beneficiary;
    uint256 public immutable override reservePrice;

     address public immutable nft;
    uint256 public immutable tokenId;
    address public immutable treasury;
    uint16 public immutable protocolFeeBps;
    bool public nftReleased;
 
    uint256 public constant MAX_BIDS_PER_ADDRESS = 20;
    uint256 public constant REVEAL_EXTENSION_WINDOW = 5 minutes;
    uint256 public constant REVEAL_EXTENSION_TIME = 5 minutes;
    uint256 public constant MAX_REVEAL_EXTENSIONS = 3;

    AuctionPhaseLib.Clock private clock;
    mapping(address => Bid[]) public bids;
    mapping(address => uint256) public pendingReturns;
    uint256 public totalPendingReturns;

    address public override highestBidder;
    uint256 public override highestBid;

     error NotSeller();
    error SellerNoLongerOwnsAsset();
    error InvalidFeeBps();
    error EscrowInvariantBroken();

    event NFTEscrowed(address indexed seller, address indexed nft, uint256 indexed tokenId);
    event NFTReleased(address indexed to, uint256 indexed tokenId);
    event ProceedsSettled(address indexed seller, uint256 sellerAmount, uint256 fee);
 
    modifier onlyInPhase(Phase _required) {
        clock.requirePhase(_required);
        _;
    }

 
    constructor(
        address initialOwner,
        address payable _beneficiary,
        address _nft,
        uint256 _tokenId,
        address _treasury,
        uint16 _protocolFeeBps,
        uint256 _biddingTime,
        uint256 _revealTime,
        uint256 _reservePrice
    ) Ownable(initialOwner) {
        if (_beneficiary == address(0)) revert ZeroAddress();
        if (_nft == address(0) || _treasury == address(0)) revert ZeroAddress();
        if (_biddingTime == 0 || _revealTime == 0) revert InvalidTimes();
        if (_protocolFeeBps > 1000) revert InvalidFeeBps();

        beneficiary = _beneficiary;
        nft = _nft;
        tokenId = _tokenId;
        treasury = _treasury;
        protocolFeeBps = _protocolFeeBps;
        reservePrice = _reservePrice;

        clock = AuctionPhaseLib.Clock({
            biddingEnd: block.timestamp + _biddingTime,
            revealEnd: block.timestamp + _biddingTime + _revealTime,
            revealExtensionsUsed: 0,
            ended: false,
            cancelled: false
        });

        emit NFTEscrowed(_beneficiary, _nft, _tokenId);
    }

    function currentPhase() public view override returns (Phase) {
        return clock.currentPhase();
    }

    function timeUntilPhaseChange() public view override returns (uint256) {
        return clock.timeRemaining();
    }

    function placeBid(bytes32 _blindedBid) external payable override whenNotPaused onlyInPhase(Phase.Bidding) {
        Bid[] storage myBids = bids[msg.sender];
        if (myBids.length >= MAX_BIDS_PER_ADDRESS) revert TooManyBids(MAX_BIDS_PER_ADDRESS);
        myBids.push(Bid({blindedBid: _blindedBid, deposit: msg.value}));
        emit BidPlaced(msg.sender, myBids.length - 1, msg.value);
    }

    function computeBlindedBid(uint256 _value, bool _fake, bytes32 _secret) public pure override returns (bytes32) {
        return keccak256(abi.encodePacked(_value, _fake, _secret));
    }

    function reveal(uint256[] calldata _values, bool[] calldata _fakes, bytes32[] calldata _secrets)
        external
        override
        nonReentrant
        whenNotPaused
        onlyInPhase(Phase.Reveal)
    {
        uint256 length = bids[msg.sender].length;
        if (_values.length != length || _fakes.length != length || _secrets.length != length) {
            revert ArrayLengthMismatch();
        }

        Bid[] storage myBids = bids[msg.sender];
        uint256 refund;

        for (uint256 i; i < length; ++i) {
            Bid storage bidToCheck = myBids[i];
            uint256 value = _values[i];
            bool fake = _fakes[i];
            bytes32 secret = _secrets[i];

            if (bidToCheck.blindedBid != keccak256(abi.encodePacked(value, fake, secret))) {
                emit BidRevealed(msg.sender, i, value, false);
                continue;
            }

            bidToCheck.blindedBid = bytes32(0);
            refund += bidToCheck.deposit;

            if (!fake && bidToCheck.deposit >= value) {
                bool becameHighest = _tryPlaceRevealedBid(msg.sender, value);
                if (becameHighest) refund -= value;
                emit BidRevealed(msg.sender, i, value, true);
            }
        }

        if (refund > 0) _creditPendingReturn(msg.sender, refund);
        clock.tryExtendReveal(REVEAL_EXTENSION_WINDOW, REVEAL_EXTENSION_TIME, MAX_REVEAL_EXTENSIONS);
    }

 
    function finalizeAuction() external override nonReentrant whenNotPaused onlyInPhase(Phase.AwaitingFinalization) {
        clock.ended = true;
        bool reserveMet = highestBidder != address(0) && highestBid >= reservePrice;

        if (reserveMet) {
            address winner = highestBidder;
            uint256 amount = highestBid;
            highestBid = 0;
            highestBidder = address(0);

            if (ICustomNFT(nft).ownerOf(tokenId) != address(this)) revert SellerNoLongerOwnsAsset();
            _releaseNFT(winner);
            _settleSeller(amount);

            emit AuctionFinalized(winner, amount, true);
        } else {
            if (highestBidder != address(0)) {
                _creditPendingReturn(highestBidder, highestBid);
                highestBid = 0;
                highestBidder = address(0);
            }
            _releaseNFT(beneficiary);
            emit AuctionFinalized(address(0), 0, false);
        }

        _assertEscrowInvariant();
    }

    function withdraw() external override nonReentrant whenNotPaused {
        uint256 amount = pendingReturns[msg.sender];
        if (amount == 0) revert NothingToWithdraw();

        pendingReturns[msg.sender] = 0;
        totalPendingReturns -= amount;
        (bool success,) = payable(msg.sender).call{value: amount}("");
        if (!success) revert TransferFailed();
        emit Withdrawn(msg.sender, amount);
    }
 
    function cancelAuction() external override onlyOwner {
        Phase current = clock.currentPhase();
        if (current == Phase.Ended || current == Phase.Cancelled) revert AlreadyFinalized();
        clock.cancelled = true;

        if (highestBidder != address(0)) {
            _creditPendingReturn(highestBidder, highestBid);
            highestBid = 0;
            highestBidder = address(0);
        }

        _releaseNFT(beneficiary);

        emit AuctionCancelled(msg.sender, block.timestamp);
    }

    function pause() external override onlyOwner {
        _pause();
    }

    function unpause() external override onlyOwner {
        _unpause();
    }

    function withdrawIfCancelled() external override nonReentrant onlyInPhase(Phase.Cancelled) {
        Bid[] storage myBids = bids[msg.sender];
        uint256 refund;

        for (uint256 i; i < myBids.length; ++i) {
            refund += myBids[i].deposit;
            myBids[i].deposit = 0;
        }

        uint256 alreadyPending = pendingReturns[msg.sender];
        if (alreadyPending > 0) {
            refund += alreadyPending;
            pendingReturns[msg.sender] = 0;
            totalPendingReturns -= alreadyPending;
        }

        if (refund == 0) revert NothingToWithdraw();

        (bool success,) = payable(msg.sender).call{value: refund}("");
        if (!success) revert TransferFailed();
        emit CancelledRefund(msg.sender, refund);
    }

    function biddingEnd() external view override returns (uint256) {
        return clock.biddingEnd;
    }

    function revealEnd() external view override returns (uint256) {
        return clock.revealEnd;
    }

    function revealExtensionsUsed() external view override returns (uint256) {
        return clock.revealExtensionsUsed;
    }

    function auctionEnded() external view override returns (bool) {
        return clock.ended;
    }

    function auctionCancelled() external view override returns (bool) {
        return clock.cancelled;
    }

    function getMyBidCount() external view override returns (uint256) {
        return bids[msg.sender].length;
    }

    function getBidCount(address _bidder) external view override returns (uint256) {
        return bids[_bidder].length;
    }

    function getPendingReturn(address _bidder) external view override returns (uint256) {
        return pendingReturns[_bidder];
    }

    function _tryPlaceRevealedBid(address _bidder, uint256 _value) internal returns (bool) {
        if (_value <= highestBid) return false;
        if (highestBidder != address(0)) _creditPendingReturn(highestBidder, highestBid);

        highestBid = _value;
        highestBidder = _bidder;
        emit HighestBidIncreased(_bidder, _value);
        return true;
    }

    function _creditPendingReturn(address bidder, uint256 amount) internal {
        if (amount == 0) return;
        pendingReturns[bidder] += amount;
        totalPendingReturns += amount;
    }
 
    function _releaseNFT(address to) internal {
        if (nftReleased) return;
        nftReleased = true;
        ICustomNFT(nft).transferFrom(address(this), to, tokenId);
        emit NFTReleased(to, tokenId);
    }
 
    function _settleSeller(uint256 amount) internal {
        (uint256 fee, uint256 sellerAmount) = FeeMath.split(amount, protocolFeeBps);

        if (fee > 0) {
            ITreasury(treasury).credit{value: fee}(
                ITreasury(treasury).feeRecipientForProtocol(),
                keccak256("BLIND_AUCTION_FEE")
            );
        }

        ITreasury(treasury).credit{value: sellerAmount}(beneficiary, keccak256("BLIND_AUCTION_PROCEEDS"));

        emit ProceedsSettled(beneficiary, sellerAmount, fee);
    }

    function _assertEscrowInvariant() internal view {
        if (address(this).balance < totalPendingReturns) revert EscrowInvariantBroken();
    }

    receive() external payable {
        revert DirectPaymentNotAllowed();
    }
}

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
    mapping(bytes32 => bool) public commitmentUsed;
    mapping(address => uint256) public pendingReturns;
    uint256 public totalPendingReturns;
    uint256 public override totalUnrevealedDeposits;
    address public override highestBidder;
    uint256 public override highestBid;
    error NotSeller();
    error SellerNoLongerOwnsAsset();
    error InvalidFeeBps();
    error EscrowInvariantBroken();
    error CommitmentAlreadyUsed();
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
        if (_nft.code.length == 0 || _treasury.code.length == 0) revert ZeroAddress();
        if (_biddingTime == 0 || _revealTime == 0) revert InvalidTimes();
        if (_biddingTime > type(uint64).max || _revealTime > type(uint64).max) revert InvalidTimes();
        if (_biddingTime + _revealTime > type(uint64).max - block.timestamp) revert InvalidTimes();
        if (_protocolFeeBps > 1000) revert InvalidFeeBps();
        beneficiary = _beneficiary;
        nft = _nft;
        tokenId = _tokenId;
        treasury = _treasury;
        protocolFeeBps = _protocolFeeBps;
        reservePrice = _reservePrice;
        clock = AuctionPhaseLib.Clock({
            biddingEnd: uint64(block.timestamp + _biddingTime),
            revealEnd: uint64(block.timestamp + _biddingTime + _revealTime),
            revealExtensionsUsed: 0,
            ended: false,
            cancelled: false
        });
    }

    function automationReady() external view returns (bool) {
        return !paused() && clock.currentPhase() == Phase.AwaitingFinalization;
    }

    function currentPhase() public view override returns (Phase) {
        return clock.currentPhase();
    }

    function timeUntilPhaseChange() public view override returns (uint256) {
        return clock.timeRemaining();
    }

    function placeBid(bytes32 _blindedBid) external payable override whenNotPaused onlyInPhase(Phase.Bidding) {
        if (ICustomNFT(nft).ownerOf(tokenId) != address(this)) revert SellerNoLongerOwnsAsset();
        if (msg.sender == beneficiary) revert SellerCannotBid();
        Bid[] storage myBids = bids[msg.sender];
        if (myBids.length >= MAX_BIDS_PER_ADDRESS) revert TooManyBids(MAX_BIDS_PER_ADDRESS);
        if (commitmentUsed[_blindedBid]) revert CommitmentAlreadyUsed();
        commitmentUsed[_blindedBid] = true;
        myBids.push(Bid({ blindedBid: _blindedBid, deposit: msg.value }));
        totalUnrevealedDeposits += msg.value;
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

        uint256 refund;
        bool anyValidReveal;
        for (uint256 i; i < length; ++i) {
            (uint256 refundDelta, bool validReveal) = _revealSingleBid(i, _values[i], _fakes[i], _secrets[i]);
            refund += refundDelta;
            anyValidReveal = anyValidReveal || validReveal;
        }

        if (refund > 0) _creditPendingReturn(msg.sender, refund);
        if (anyValidReveal) {
            clock.tryExtendReveal(REVEAL_EXTENSION_WINDOW, REVEAL_EXTENSION_TIME, MAX_REVEAL_EXTENSIONS);
        }
    }

    function _revealSingleBid(uint256 index, uint256 value, bool fake, bytes32 secret)
        internal
        returns (uint256 refundDelta, bool validReveal)
    {
        address bidder = msg.sender;
        Bid storage bidToCheck = bids[bidder][index];
        if (bidToCheck.blindedBid != keccak256(abi.encodePacked(value, fake, secret))) {
            emit BidRevealed(bidder, index, value, false);
            return (0, false);
        }
        validReveal = true;

        bidToCheck.blindedBid = bytes32(0);
        uint256 deposit = bidToCheck.deposit;
        bidToCheck.deposit = 0;
        totalUnrevealedDeposits -= deposit;
        refundDelta = deposit;

        if (!fake && deposit >= value) {
            bool becameHighest = _tryPlaceRevealedBid(bidder, value);
            if (becameHighest) refundDelta -= value;
            emit BidRevealed(bidder, index, value, true);
        }
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

    function withdraw() external override nonReentrant {
        uint256 amount = pendingReturns[msg.sender];
        if (amount == 0) revert NothingToWithdraw();
        pendingReturns[msg.sender] = 0;
        totalPendingReturns -= amount;
        (bool success,) = payable(msg.sender).call{ value: amount }("");
        if (!success) revert TransferFailed();
        emit Withdrawn(msg.sender, amount);
    }

    function withdrawUnrevealed() external override nonReentrant {
        Phase current = clock.currentPhase();
        if (current != Phase.AwaitingFinalization && current != Phase.Ended && current != Phase.Cancelled) {
            revert AlreadyFinalized();
        }
        Bid[] storage myBids = bids[msg.sender];
        uint256 refund;
        for (uint256 i; i < myBids.length; ++i) {
            Bid storage bid = myBids[i];
            if (bid.deposit == 0) continue;
            refund += bid.deposit;
            totalUnrevealedDeposits -= bid.deposit;
            bid.deposit = 0;
        }
        if (refund == 0) revert NothingToWithdraw();
        (bool success,) = payable(msg.sender).call{ value: refund }("");
        if (!success) revert TransferFailed();
        emit UnrevealedWithdrawn(msg.sender, refund);
        _assertEscrowInvariant();
    }

    function cancelAuction() external override onlyOwner {
        Phase current = clock.currentPhase();
        if (current != Phase.Bidding && current != Phase.Reveal) revert AlreadyFinalized();
        clock.cancelled = true;
        if (highestBidder != address(0)) {
            _creditPendingReturn(highestBidder, highestBid);
            highestBid = 0;
            highestBidder = address(0);
        }
        _releaseNFT(beneficiary);
        emit AuctionCancelled(msg.sender, block.timestamp);
        _assertEscrowInvariant();
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
            totalUnrevealedDeposits -= myBids[i].deposit;
            myBids[i].deposit = 0;
        }
        uint256 alreadyPending = pendingReturns[msg.sender];
        if (alreadyPending > 0) {
            refund += alreadyPending;
            pendingReturns[msg.sender] = 0;
            totalPendingReturns -= alreadyPending;
        }
        if (refund == 0) revert NothingToWithdraw();
        (bool success,) = payable(msg.sender).call{ value: refund }("");
        if (!success) revert TransferFailed();
        emit CancelledRefund(msg.sender, refund);
        _assertEscrowInvariant();
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
            ITreasury(treasury).credit{ value: fee }(
                ITreasury(treasury).feeRecipientForProtocol(), keccak256("BLIND_AUCTION_FEE")
            );
        }
        ITreasury(treasury).credit{ value: sellerAmount }(beneficiary, keccak256("BLIND_AUCTION_PROCEEDS"));
        emit ProceedsSettled(beneficiary, sellerAmount, fee);
    }

    function _assertEscrowInvariant() internal view {
        uint256 expected = highestBid + totalPendingReturns + totalUnrevealedDeposits;
        if (address(this).balance < expected) revert EscrowInvariantBroken();
    }

    receive() external payable {
        revert DirectPaymentNotAllowed();
    }
}

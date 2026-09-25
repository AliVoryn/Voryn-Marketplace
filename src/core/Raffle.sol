// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable2Step.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { VRFV2PlusClient } from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";
import { IVRFCoordinatorV2Plus } from "@chainlink/contracts/src/v0.8/vrf/dev/interfaces/IVRFCoordinatorV2Plus.sol";
import { ICustomNFT } from "../interfaces/ICustomNFT.sol";
import { IRaffle } from "../interfaces/IRaffle.sol";
import { ITreasury } from "../interfaces/ITreasury.sol";
import { FeeMath } from "../libraries/FeeMath.sol";
import { RaffleMath } from "../libraries/RaffleMath.sol";
import { AutomationScanLib } from "../libraries/AutomationScanLib.sol";

contract Raffle is Ownable2Step, ReentrancyGuard, Pausable, IRaffle {
    uint16 public constant MAX_FEE_BPS = 1000;
    uint64 public constant RANDOMNESS_RETRY_DELAY = 1 hours;
    uint64 public constant STUCK_RAFFLE_CANCEL_DELAY = 24 hours;
    uint256 public constant MAX_REFUND_BATCH = 100;
    address public immutable treasury;
    uint16 public feeBps;
    address public vrfCoordinator;
    uint256 public subscriptionId;
    bytes32 public keyHash;
    uint32 public callbackGasLimit;
    uint16 public requestConfirmations;
    bool public nativePayment;
    uint256 private nextRaffleId = 1;
    mapping(uint256 => RaffleData) private raffles;
    mapping(uint256 => Entrant[]) private raffleEntrants;
    mapping(uint256 => mapping(address => uint256)) private ticketsBought;
    mapping(uint256 => uint256) private requestIdToRaffleId;
    mapping(uint256 => address) private requestIdToCoordinator;
    mapping(uint256 => uint256) public refundCursor;
    mapping(address => uint256) public raffleRefunds;
    uint256 public totalActiveRaffleFunds;
    uint256 public totalRaffleRefundLiability;

    constructor(
        address initialOwner,
        address treasury_,
        uint16 feeBps_,
        address vrfCoordinator_,
        uint256 subscriptionId_,
        bytes32 keyHash_,
        uint32 callbackGasLimit_,
        uint16 requestConfirmations_,
        bool nativePayment_
    ) Ownable(initialOwner) {
        if (treasury_ == address(0)) revert ZeroAddress();
        if (treasury_.code.length == 0) revert ZeroAddress();
        if (feeBps_ > MAX_FEE_BPS) revert InvalidFeeBps();
        _validateVRFConfig(vrfCoordinator_, subscriptionId_, keyHash_, callbackGasLimit_, requestConfirmations_);
        treasury = treasury_;
        feeBps = feeBps_;
        vrfCoordinator = vrfCoordinator_;
        subscriptionId = subscriptionId_;
        keyHash = keyHash_;
        callbackGasLimit = callbackGasLimit_;
        requestConfirmations = requestConfirmations_;
        nativePayment = nativePayment_;
    }

    function createRaffle(
        address nft,
        uint256 tokenId,
        uint256 ticketPrice,
        uint256 maxTickets,
        uint256 maxTicketsPerWallet,
        uint64 startAt,
        uint64 duration
    ) external override nonReentrant whenNotPaused returns (uint256 raffleId) {
        if (nft == address(0)) revert ZeroAddress();
        if (nft.code.length == 0) revert UnsupportedAsset();
        if (ticketPrice == 0) revert InvalidTicketPrice();
        if (duration == 0) revert InvalidTime();
        if (startAt != 0 && startAt < block.timestamp) revert InvalidTime();
        if (maxTickets > type(uint128).max) revert InvalidMaxTickets();
        if (ICustomNFT(nft).ownerOf(tokenId) != msg.sender) revert NotCreator();

        uint64 effectiveStart = startAt == 0 ? uint64(block.timestamp) : startAt;
        if (uint256(effectiveStart) > type(uint64).max - duration) revert InvalidTime();
        uint64 effectiveEnd = effectiveStart + duration;
        raffleId = nextRaffleId++;

        RaffleData storage r = raffles[raffleId];
        r.id = raffleId;
        r.creator = msg.sender;
        r.nft = nft;
        r.tokenId = tokenId;
        r.ticketPrice = ticketPrice;
        r.maxTickets = maxTickets;
        r.maxTicketsPerWallet = maxTicketsPerWallet;
        r.startAt = effectiveStart;
        r.endAt = effectiveEnd;
        r.phase = effectiveStart > block.timestamp ? RafflePhase.Created : RafflePhase.Active;

        ICustomNFT(nft).transferFrom(msg.sender, address(this), tokenId);
        emit RaffleCreated(raffleId, msg.sender, nft, tokenId, ticketPrice, maxTickets, effectiveStart, effectiveEnd);
    }

    function buyTickets(uint256 raffleId, uint256 quantity) external payable override nonReentrant whenNotPaused {
        RaffleData storage r = _existingRaffle(raffleId);
        if (r.phase == RafflePhase.Created && block.timestamp >= r.startAt) {
            r.phase = RafflePhase.Active;
        }
        if (r.phase != RafflePhase.Active) revert InvalidPhase();
        if (block.timestamp >= r.endAt) revert RaffleEnded();
        if (quantity == 0) revert InvalidQuantity();
        if (r.maxTickets != 0 && quantity > r.maxTickets - r.ticketsSold) revert SoldOut();
        if (quantity > type(uint128).max || r.ticketsSold > type(uint128).max - quantity) revert InvalidQuantity();

        uint256 walletTotal = ticketsBought[raffleId][msg.sender] + quantity;
        if (r.maxTicketsPerWallet != 0 && walletTotal > r.maxTicketsPerWallet) revert TicketLimitExceeded();
        if (quantity > type(uint256).max / r.ticketPrice) revert IncorrectPayment();
        uint256 cost = r.ticketPrice * quantity;
        if (msg.value != cost) revert IncorrectPayment();

        uint256 startIndex = r.ticketsSold;
        raffleEntrants[raffleId].push(
            Entrant({ buyer: msg.sender, startIndex: uint128(startIndex), ticketCount: uint128(quantity) })
        );
        r.ticketsSold = startIndex + quantity;
        ticketsBought[raffleId][msg.sender] = walletTotal;
        totalActiveRaffleFunds += cost;
        emit TicketsPurchased(raffleId, msg.sender, quantity, startIndex, cost);

        if (r.maxTickets != 0 && r.ticketsSold == r.maxTickets) {
            _requestRandomWinner(raffleId, r);
        }
        _assertInvariant();
    }

    function requestRandomWinner(uint256 raffleId) external override nonReentrant whenNotPaused {
        RaffleData storage r = _existingRaffle(raffleId);
        if (r.phase == RafflePhase.Created && block.timestamp >= r.startAt) r.phase = RafflePhase.Active;
        if (r.phase != RafflePhase.Active) revert InvalidPhase();
        if (block.timestamp < r.endAt) revert RaffleNotYetEnded();
        if (r.ticketsSold == 0) revert NoTicketsSold();
        _requestRandomWinner(raffleId, r);
    }

    function retryRandomWinnerRequest(uint256 raffleId) external override onlyOwner nonReentrant {
        RaffleData storage r = _existingRaffle(raffleId);
        if (r.phase != RafflePhase.AwaitingRandomness) revert InvalidPhase();
        if (block.timestamp < uint256(r.randomnessRequestedAt) + RANDOMNESS_RETRY_DELAY) revert RandomnessNotYetDue();
        uint256 oldRequestId = r.vrfRequestId;
        delete requestIdToRaffleId[oldRequestId];
        delete requestIdToCoordinator[oldRequestId];
        r.phase = RafflePhase.Active;
        _requestRandomWinner(raffleId, r);
        emit RandomnessRetried(raffleId, oldRequestId, r.vrfRequestId);
    }

    function cancelStuckRaffle(uint256 raffleId) external override nonReentrant {
        RaffleData storage r = _existingRaffle(raffleId);
        if (msg.sender != r.creator && msg.sender != owner()) revert NotCreator();
        if (r.phase != RafflePhase.AwaitingRandomness) revert InvalidPhase();
        if (block.timestamp < uint256(r.randomnessRequestedAt) + STUCK_RAFFLE_CANCEL_DELAY) {
            revert RandomnessNotYetDue();
        }
        delete requestIdToRaffleId[r.vrfRequestId];
        delete requestIdToCoordinator[r.vrfRequestId];
        r.phase = RafflePhase.Cancelled;
        ICustomNFT(r.nft).transferFrom(address(this), r.creator, r.tokenId);
        emit RaffleCancelled(raffleId);
        _assertInvariant();
    }

    function processRaffleRefunds(uint256 raffleId, uint256 maxEntries) external override nonReentrant {
        RaffleData storage r = _existingRaffle(raffleId);
        if (r.phase != RafflePhase.Cancelled) revert InvalidPhase();
        if (maxEntries == 0 || maxEntries > MAX_REFUND_BATCH) revert InvalidQuantity();

        Entrant[] storage entrants = raffleEntrants[raffleId];
        uint256 cursor = refundCursor[raffleId];
        uint256 length = entrants.length;
        if (cursor >= length) revert InvalidQuantity();
        uint256 end = cursor + maxEntries;
        if (end > length) end = length;
        for (uint256 i = cursor; i < end; ++i) {
            Entrant memory entrant = entrants[i];
            uint256 amount = uint256(entrant.ticketCount) * r.ticketPrice;
            raffleRefunds[entrant.buyer] += amount;
            totalRaffleRefundLiability += amount;
            totalActiveRaffleFunds -= amount;
            emit RaffleRefundCredited(raffleId, entrant.buyer, amount);
        }
        refundCursor[raffleId] = end;
        _assertInvariant();
    }

    struct AutomationRefundCandidate {
        uint256 raffleId;
        uint256 cursor;
    }

    function automationCandidates(uint256 cycle, uint256 maxScan, uint256 maxItems)
        external
        view
        returns (
            uint256[] memory winnerRequestIds,
            uint256[] memory failedIds,
            AutomationRefundCandidate[] memory refundCandidates
        )
    {
        if (maxItems == 0 || maxScan == 0 || paused()) {
            return (new uint256[](0), new uint256[](0), new AutomationRefundCandidate[](0));
        }

        (uint256 startId, uint256 endId) = AutomationScanLib.window(nextRaffleId - 1, cycle, maxScan);
        return _scanAutomationCandidates(startId, endId, AutomationScanLib.capacity(maxItems, startId, endId));
    }

    function _scanAutomationCandidates(uint256 startId, uint256 endId, uint256 capacity)
        internal
        view
        returns (
            uint256[] memory winnerRequestIds,
            uint256[] memory failedIds,
            AutomationRefundCandidate[] memory refundCandidates
        )
    {
        winnerRequestIds = new uint256[](capacity);
        failedIds = new uint256[](capacity);
        refundCandidates = new AutomationRefundCandidate[](capacity);
        uint256 winnerCount;
        uint256 failedCount;
        uint256 refundCount;

        for (uint256 id = startId; id < endId; ++id) {
            RaffleData storage r = raffles[id];
            if (r.creator == address(0)) continue;

            if (
                winnerCount < capacity && r.phase == RafflePhase.Active && r.ticketsSold > 0
                    && ((r.maxTickets != 0 && r.ticketsSold == r.maxTickets) || block.timestamp >= r.endAt)
            ) {
                winnerRequestIds[winnerCount++] = id;
                continue;
            }

            if (
                failedCount < capacity && (r.phase == RafflePhase.Created || r.phase == RafflePhase.Active)
                    && r.ticketsSold == 0 && r.endAt != 0 && block.timestamp >= r.endAt
            ) {
                failedIds[failedCount++] = id;
                continue;
            }

            if (refundCount < capacity && r.phase == RafflePhase.Cancelled) {
                uint256 cursor = refundCursor[id];
                if (cursor < raffleEntrants[id].length) {
                    refundCandidates[refundCount++] = AutomationRefundCandidate(id, cursor);
                }
            }
        }

        assembly {
            mstore(winnerRequestIds, winnerCount)
            mstore(failedIds, failedCount)
            mstore(refundCandidates, refundCount)
        }
    }

    function claimRaffleRefund() external override nonReentrant {
        uint256 amount = raffleRefunds[msg.sender];
        if (amount == 0) revert RaffleRefundUnavailable();
        raffleRefunds[msg.sender] = 0;
        totalRaffleRefundLiability -= amount;
        (bool success,) = payable(msg.sender).call{ value: amount }("");
        if (!success) revert TransferFailed();
        emit RaffleRefundClaimed(msg.sender, amount);
        _assertInvariant();
    }

    function _requestRandomWinner(uint256 raffleId, RaffleData storage r) internal {
        r.phase = RafflePhase.AwaitingRandomness;
        r.randomnessRequestedAt = uint64(block.timestamp);
        address coordinator = vrfCoordinator;
        uint256 requestId = IVRFCoordinatorV2Plus(coordinator)
            .requestRandomWords(
                VRFV2PlusClient.RandomWordsRequest({
                    keyHash: keyHash,
                    subId: subscriptionId,
                    requestConfirmations: requestConfirmations,
                    callbackGasLimit: callbackGasLimit,
                    numWords: 1,
                    extraArgs: VRFV2PlusClient._argsToBytes(
                        VRFV2PlusClient.ExtraArgsV1({ nativePayment: nativePayment })
                    )
                })
            );
        r.vrfRequestId = requestId;
        requestIdToRaffleId[requestId] = raffleId;
        requestIdToCoordinator[requestId] = coordinator;
        emit RandomnessRequested(raffleId, requestId);
    }

    function rawFulfillRandomWords(uint256 requestId, uint256[] calldata randomWords) external nonReentrant {
        uint256 raffleId = requestIdToRaffleId[requestId];
        address expectedCoordinator = requestIdToCoordinator[requestId];
        if (expectedCoordinator == address(0) || raffleId == 0) revert UnknownRequestId();
        if (msg.sender != expectedCoordinator) revert OnlyCoordinatorCanFulfill();
        if (randomWords.length != 1) revert InvalidRandomnessResponse();

        RaffleData storage r = raffles[raffleId];
        if (r.phase != RafflePhase.AwaitingRandomness || r.vrfRequestId != requestId) revert UnknownRequestId();
        delete requestIdToRaffleId[requestId];
        delete requestIdToCoordinator[requestId];

        uint256 winningTicketIndex = RaffleMath.pickWinningTicket(randomWords[0], r.ticketsSold);
        address winner = RaffleMath.findEntrant(raffleEntrants[raffleId], winningTicketIndex);
        r.phase = RafflePhase.Finalized;
        r.winner = winner;
        uint256 proceeds = r.ticketPrice * r.ticketsSold;
        totalActiveRaffleFunds -= proceeds;

        (uint256 fee, uint256 creatorAmount) = FeeMath.split(proceeds, feeBps);
        if (fee > 0) {
            ITreasury(treasury).credit{ value: fee }(
                ITreasury(treasury).feeRecipientForProtocol(), keccak256("RAFFLE_FEE")
            );
        }
        ITreasury(treasury).credit{ value: creatorAmount }(r.creator, keccak256("RAFFLE_PROCEEDS"));
        ICustomNFT(r.nft).transferFrom(address(this), winner, r.tokenId);
        emit RaffleFinalized(raffleId, winner, winningTicketIndex, proceeds);
        _assertInvariant();
    }

    function finalizeFailedRaffle(uint256 raffleId) external override nonReentrant {
        RaffleData storage r = _existingRaffle(raffleId);
        if (r.phase == RafflePhase.Created && block.timestamp >= r.startAt) r.phase = RafflePhase.Active;
        if (r.phase != RafflePhase.Active) revert InvalidPhase();
        if (block.timestamp < r.endAt) revert RaffleNotYetEnded();
        if (r.ticketsSold != 0) revert InvalidPhase();
        r.phase = RafflePhase.Failed;
        ICustomNFT(r.nft).transferFrom(address(this), r.creator, r.tokenId);
        emit RaffleFailed(raffleId);
    }

    function cancelRaffle(uint256 raffleId) external override nonReentrant {
        RaffleData storage r = _existingRaffle(raffleId);
        if (msg.sender != r.creator && msg.sender != owner()) revert NotCreator();
        if (r.phase != RafflePhase.Active && r.phase != RafflePhase.Created) revert InvalidPhase();
        if (r.ticketsSold != 0) revert TicketsAlreadySold();
        r.phase = RafflePhase.Cancelled;
        ICustomNFT(r.nft).transferFrom(address(this), r.creator, r.tokenId);
        emit RaffleCancelled(raffleId);
    }

    function setFeeBps(uint16 bps) external onlyOwner {
        if (bps > MAX_FEE_BPS) revert InvalidFeeBps();
        feeBps = bps;
        emit FeeConfigUpdated(bps);
    }

    function setVRFConfig(
        address vrfCoordinator_,
        uint256 subscriptionId_,
        bytes32 keyHash_,
        uint32 callbackGasLimit_,
        uint16 requestConfirmations_,
        bool nativePayment_
    ) external onlyOwner {
        _validateVRFConfig(vrfCoordinator_, subscriptionId_, keyHash_, callbackGasLimit_, requestConfirmations_);
        vrfCoordinator = vrfCoordinator_;
        subscriptionId = subscriptionId_;
        keyHash = keyHash_;
        callbackGasLimit = callbackGasLimit_;
        requestConfirmations = requestConfirmations_;
        nativePayment = nativePayment_;
        emit VRFConfigUpdated(
            vrfCoordinator_, subscriptionId_, keyHash_, callbackGasLimit_, requestConfirmations_, nativePayment_
        );
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function getRaffle(uint256 raffleId) external view override returns (RaffleData memory) {
        RaffleData memory r = raffles[raffleId];
        if (r.creator == address(0)) revert RaffleNotFound();
        return r;
    }

    function raffleCount() external view override returns (uint256) {
        return nextRaffleId - 1;
    }

    function ticketsOwnedBy(uint256 raffleId, address buyer) external view override returns (uint256) {
        return ticketsBought[raffleId][buyer];
    }

    function entrantCount(uint256 raffleId) external view returns (uint256) {
        return raffleEntrants[raffleId].length;
    }

    function entrantAt(uint256 raffleId, uint256 index) external view returns (Entrant memory) {
        return raffleEntrants[raffleId][index];
    }

    function _existingRaffle(uint256 raffleId) internal view returns (RaffleData storage r) {
        r = raffles[raffleId];
        if (r.creator == address(0)) revert RaffleNotFound();
    }

    function _validateVRFConfig(
        address vrfCoordinator_,
        uint256 subscriptionId_,
        bytes32 keyHash_,
        uint32 callbackGasLimit_,
        uint16 requestConfirmations_
    ) internal view {
        if (vrfCoordinator_ == address(0)) revert ZeroAddress();
        if (vrfCoordinator_.code.length == 0) revert InvalidVRFCoordinator();
        if (subscriptionId_ == 0 || keyHash_ == bytes32(0) || callbackGasLimit_ == 0) revert InvalidVRFConfig();
        if (requestConfirmations_ < 3 || requestConfirmations_ > 200) revert InvalidVRFConfig();
    }

    function _assertInvariant() internal view {
        uint256 expected = totalActiveRaffleFunds + totalRaffleRefundLiability;
        if (address(this).balance < expected) revert EscrowInvariantBroken();
    }

    receive() external payable {
        revert DirectPaymentNotAllowed();
    }
}

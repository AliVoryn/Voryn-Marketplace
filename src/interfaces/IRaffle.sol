// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IRaffle {
    enum RafflePhase {
        Created,
        Active,
        AwaitingRandomness,
        Finalized,
        Cancelled,
        Failed
    }

    struct Entrant {
        address buyer;
        uint128 startIndex;
        uint128 ticketCount;
    }

    struct RaffleData {
        uint256 id;
        address creator;
        address nft;
        uint256 tokenId;
        uint256 ticketPrice;
        uint256 maxTickets;
        uint256 maxTicketsPerWallet;
        uint256 ticketsSold;
        uint64 startAt;
        uint64 endAt;
        RafflePhase phase;
        address winner;
        uint256 vrfRequestId;
        uint64 randomnessRequestedAt;
    }
    event RaffleCreated(
        uint256 indexed raffleId,
        address indexed creator,
        address indexed nft,
        uint256 tokenId,
        uint256 ticketPrice,
        uint256 maxTickets,
        uint64 startAt,
        uint64 endAt
    );
    event TicketsPurchased(
        uint256 indexed raffleId, address indexed buyer, uint256 quantity, uint256 startIndex, uint256 totalCost
    );
    event RandomnessRequested(uint256 indexed raffleId, uint256 indexed requestId);
    event RandomnessRetried(uint256 indexed raffleId, uint256 indexed oldRequestId, uint256 indexed newRequestId);
    event RaffleFinalized(
        uint256 indexed raffleId, address indexed winner, uint256 winningTicketIndex, uint256 proceeds
    );
    event RaffleCancelled(uint256 indexed raffleId);
    event RaffleRefundCredited(uint256 indexed raffleId, address indexed buyer, uint256 amount);
    event RaffleRefundClaimed(address indexed buyer, uint256 amount);
    event RaffleFailed(uint256 indexed raffleId);
    event FeeConfigUpdated(uint16 feeBps);
    event VRFConfigUpdated(
        address vrfCoordinator,
        uint256 subscriptionId,
        bytes32 keyHash,
        uint32 callbackGasLimit,
        uint16 requestConfirmations,
        bool nativePayment
    );
    error ZeroAddress();
    error UnsupportedAsset();
    error InvalidFeeBps();
    error InvalidTicketPrice();
    error InvalidTime();
    error InvalidMaxTickets();
    error NotCreator();
    error InvalidPhase();
    error RaffleNotFound();
    error SoldOut();
    error TicketLimitExceeded();
    error InvalidQuantity();
    error IncorrectPayment();
    error RaffleEnded();
    error RaffleNotYetEnded();
    error RaffleRefundUnavailable();
    error TransferFailed();
    error NoTicketsSold();
    error TicketsAlreadySold();
    error RandomnessNotYetDue();
    error UnknownRequestId();
    error OnlyCoordinatorCanFulfill();
    error InvalidRandomnessResponse();
    error EntrantNotFound();
    error EscrowInvariantBroken();
    error DirectPaymentNotAllowed();
    error InvalidVRFConfig();
    error InvalidVRFCoordinator();
    function createRaffle(
        address nft,
        uint256 tokenId,
        uint256 ticketPrice,
        uint256 maxTickets,
        uint256 maxTicketsPerWallet,
        uint64 startAt,
        uint64 duration
    ) external returns (uint256 raffleId);
    function buyTickets(uint256 raffleId, uint256 quantity) external payable;
    function requestRandomWinner(uint256 raffleId) external;
    function retryRandomWinnerRequest(uint256 raffleId) external;
    function finalizeFailedRaffle(uint256 raffleId) external;
    function cancelRaffle(uint256 raffleId) external;
    function cancelStuckRaffle(uint256 raffleId) external;
    function processRaffleRefunds(uint256 raffleId, uint256 maxEntries) external;
    function claimRaffleRefund() external;
    function getRaffle(uint256 raffleId) external view returns (RaffleData memory);
    function raffleCount() external view returns (uint256);
    function ticketsOwnedBy(uint256 raffleId, address buyer) external view returns (uint256);
}

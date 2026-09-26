// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable2Step.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { ReceiverTemplate } from "./chainlink/ReceiverTemplate.sol";
import { IAuction } from "../interfaces/IAuction.sol";
import { IBlindAuction } from "../interfaces/IBlindAuction.sol";
import { IDutchAuction } from "../interfaces/IDutchAuction.sol";
import { IMarketplace } from "../interfaces/IMarketplace.sol";
import { IRaffle } from "../interfaces/IRaffle.sol";
import { IRegistry } from "../interfaces/IRegistry.sol";

interface IRaffleAutomationView {
    function refundCursor(uint256 raffleId) external view returns (uint256);
}

contract ProtocolAutomationReceiver is ReceiverTemplate, Ownable2Step, Pausable {
    enum Action {
        FINALIZE_OPEN_AUCTION,
        FINALIZE_BLIND_AUCTION,
        EXPIRE_DUTCH_AUCTION,
        EXPIRE_OFFER,
        REQUEST_RAFFLE_WINNER,
        PROCESS_RAFFLE_REFUNDS,
        FINALIZE_FAILED_RAFFLE
    }

    struct AutomationAction {
        Action action;
        address instance;
        uint256 id;
        uint256 value;
        uint256 cursor;
        uint64 scheduledAt;
        uint64 chainSelector;
    }

    bytes32 public constant KIND_MARKETPLACE = keccak256("MARKETPLACE");
    bytes32 public constant KIND_OPEN_AUCTION = keccak256("OPEN_AUCTION");
    bytes32 public constant KIND_BLIND_AUCTION = keccak256("BLIND_AUCTION");
    bytes32 public constant KIND_DUTCH_AUCTION = keccak256("DUTCH_AUCTION");
    bytes32 public constant KIND_RAFFLE = keccak256("RAFFLE");

    uint256 public constant MAX_REFUND_BATCH = 100;
    uint64 public constant MAX_FUTURE_SKEW = 10 minutes;

    IRegistry public immutable registry;
    uint64 public immutable expectedChainSelector;

    mapping(bytes32 => bool) public processedOperations;

    error InvalidForwarder();
    error InvalidRegistry();
    error InvalidChainSelector();
    error WorkflowNotConfigured();
    error InvalidReport();
    error InvalidAction();
    error InvalidInstance();
    error InactiveInstance();
    error InvalidTargetKind(bytes32 expected, bytes32 actual);
    error InvalidSchedule();
    error ReplayOrStaleReport();
    error InvalidActionId();
    error InvalidActionValue();
    error InvalidRefundBatch();
    error InvalidRefundCursor();
    error AutomationPaused();

    event AutomationActionExecuted(
        Action indexed action,
        address indexed instance,
        uint256 indexed id,
        uint256 value,
        uint256 cursor,
        uint64 scheduledAt
    );

    constructor(address initialOwner, address forwarder_, address registry_, uint64 chainSelector_)
        ReceiverTemplate(forwarder_)
    {
        if (initialOwner == address(0)) revert OwnableInvalidOwner(address(0));
        if (forwarder_.code.length == 0) revert InvalidForwarder();
        if (registry_ == address(0) || registry_.code.length == 0) revert InvalidRegistry();
        if (chainSelector_ == 0) revert InvalidChainSelector();
        registry = IRegistry(registry_);
        expectedChainSelector = chainSelector_;
        _transferOwnership(initialOwner);
        _pause();
    }

    function currentTimestamp() external view returns (uint256) {
        return block.timestamp;
    }

    function workflowConfigured() external view returns (bool) {
        return this.getExpectedWorkflowId() != bytes32(0) && this.getExpectedAuthor() != address(0);
    }

    function transferOwnership(address newOwner) public virtual override(Ownable, Ownable2Step) onlyOwner {
        Ownable2Step.transferOwnership(newOwner);
    }

    function _transferOwnership(address newOwner) internal virtual override(Ownable, Ownable2Step) {
        Ownable2Step._transferOwnership(newOwner);
    }

    function pauseAutomation() external onlyOwner {
        _pause();
    }

    function unpauseAutomation() external onlyOwner {
        if (!_workflowIdentityReady()) revert WorkflowNotConfigured();
        _unpause();
    }

    function _requiresWorkflowIdentity() internal view virtual returns (bool) {
        return true;
    }

    function _workflowIdentityReady() internal view returns (bool) {
        if (!_requiresWorkflowIdentity()) return true;
        return this.getExpectedWorkflowId() != bytes32(0) && this.getExpectedAuthor() != address(0);
    }

    function _processReport(bytes calldata report) internal override {
        if (paused()) revert AutomationPaused();

        address forwarder_ = this.getForwarderAddress();
        if (forwarder_ == address(0) || msg.sender != forwarder_) revert InvalidForwarder();
        if (!_workflowIdentityReady()) revert WorkflowNotConfigured();
        if (report.length != 224) revert InvalidReport();
        (
            uint8 actionRaw,
            address instance,
            uint256 id,
            uint256 value,
            uint256 cursor,
            uint64 scheduledAt,
            uint64 chainSelector
        ) = abi.decode(report, (uint8, address, uint256, uint256, uint256, uint64, uint64));
        if (actionRaw > uint8(Action.FINALIZE_FAILED_RAFFLE)) revert InvalidAction();
        AutomationAction memory request = AutomationAction({
            action: Action(actionRaw),
            instance: instance,
            id: id,
            value: value,
            cursor: cursor,
            scheduledAt: scheduledAt,
            chainSelector: chainSelector
        });
        _validate(request);

        bytes32 replayKey =
            keccak256(abi.encode(request.action, request.instance, request.id, request.value, request.cursor));
        if (processedOperations[replayKey]) revert ReplayOrStaleReport();

        processedOperations[replayKey] = true;

        if (request.action == Action.FINALIZE_OPEN_AUCTION) {
            IAuction(request.instance).finalizeAuction(request.id);
        } else if (request.action == Action.FINALIZE_BLIND_AUCTION) {
            IBlindAuction(request.instance).finalizeAuction();
        } else if (request.action == Action.EXPIRE_DUTCH_AUCTION) {
            IDutchAuction(request.instance).expireAuction(request.id);
        } else if (request.action == Action.EXPIRE_OFFER) {
            IMarketplace(request.instance).expireOffer(request.id);
        } else if (request.action == Action.REQUEST_RAFFLE_WINNER) {
            IRaffle(request.instance).requestRandomWinner(request.id);
        } else if (request.action == Action.PROCESS_RAFFLE_REFUNDS) {
            IRaffle(request.instance).processRaffleRefunds(request.id, request.value);
        } else if (request.action == Action.FINALIZE_FAILED_RAFFLE) {
            IRaffle(request.instance).finalizeFailedRaffle(request.id);
        } else {
            revert InvalidAction();
        }

        emit AutomationActionExecuted(
            request.action, request.instance, request.id, request.value, request.cursor, request.scheduledAt
        );
    }

    function _validate(AutomationAction memory request) internal view {
        if (uint8(request.action) > uint8(Action.FINALIZE_FAILED_RAFFLE)) revert InvalidAction();
        if (request.instance == address(0) || request.instance.code.length == 0) revert InvalidInstance();
        if (request.chainSelector != expectedChainSelector) revert InvalidChainSelector();
        if (request.scheduledAt == 0 || request.scheduledAt > block.timestamp + MAX_FUTURE_SKEW) {
            revert InvalidSchedule();
        }

        IRegistry.Record memory record = registry.getRecord(request.instance);
        if (!record.active) revert InactiveInstance();

        bytes32 expectedKind;
        if (request.action == Action.FINALIZE_OPEN_AUCTION) {
            expectedKind = KIND_OPEN_AUCTION;
        } else if (request.action == Action.FINALIZE_BLIND_AUCTION) {
            expectedKind = KIND_BLIND_AUCTION;
            if (request.id != 0) revert InvalidActionValue();
        } else if (request.action == Action.EXPIRE_DUTCH_AUCTION) {
            expectedKind = KIND_DUTCH_AUCTION;
        } else if (request.action == Action.EXPIRE_OFFER) {
            expectedKind = KIND_MARKETPLACE;
        } else if (
            request.action == Action.REQUEST_RAFFLE_WINNER || request.action == Action.PROCESS_RAFFLE_REFUNDS
                || request.action == Action.FINALIZE_FAILED_RAFFLE
        ) {
            expectedKind = KIND_RAFFLE;
        } else {
            revert InvalidAction();
        }

        if (record.kind != expectedKind) revert InvalidTargetKind(expectedKind, record.kind);

        if (request.action == Action.PROCESS_RAFFLE_REFUNDS) {
            if (request.id == 0) revert InvalidActionId();
            if (request.value == 0 || request.value > MAX_REFUND_BATCH) revert InvalidRefundBatch();
            if (IRaffleAutomationView(request.instance).refundCursor(request.id) != request.cursor) {
                revert InvalidRefundCursor();
            }
        } else {
            if (request.id == 0 && request.action != Action.FINALIZE_BLIND_AUCTION) revert InvalidActionId();
            if (request.value != 0 || request.cursor != 0) revert InvalidActionValue();
        }
    }
}

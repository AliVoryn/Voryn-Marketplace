// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../support/TestBase.sol";
import "../../src/automation/ProtocolAutomationReceiver.sol";
import "../../src/automation/ProtocolAutomationSimulationReceiver.sol";
import { IReceiver } from "../../src/automation/chainlink/IReceiver.sol";
import "../../src/interfaces/IRegistry.sol";
import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

contract AutomationForwarderMock { }

contract AutomationActionTarget {
    uint256 public callCount;
    uint256 public lastId;
    uint256 public lastValue;
    uint256 public cursor;

    function finalizeAuction(uint256 id) external {
        callCount++;
        lastId = id;
    }

    function expireAuction(uint256 id) external {
        callCount++;
        lastId = id;
    }

    function expireOffer(uint256 id) external {
        callCount++;
        lastId = id;
    }

    function requestRandomWinner(uint256 id) external {
        callCount++;
        lastId = id;
    }

    function finalizeFailedRaffle(uint256 id) external {
        callCount++;
        lastId = id;
    }

    function finalizeAuction() external {
        callCount++;
    }

    function processRaffleRefunds(uint256 id, uint256 value) external {
        callCount++;
        lastId = id;
        lastValue = value;
        cursor += value;
    }

    function refundCursor(uint256) external view returns (uint256) {
        return cursor;
    }
}

contract ProtocolAutomationReceiverTest is ProtocolTestBase {
    ProtocolRegistry internal registry;
    ProtocolAutomationReceiver internal receiver;
    AutomationForwarderMock internal forwarder;
    uint64 internal constant CHAIN_SELECTOR = 16015286601757825753;
    bytes32 internal constant WORKFLOW_ID = keccak256("ali-voryn-automation");
    address internal workflowAuthor = makeAddr("workflow-author");

    AutomationActionTarget internal openTarget;
    AutomationActionTarget internal blindTarget;
    AutomationActionTarget internal dutchTarget;
    AutomationActionTarget internal marketplaceTarget;
    AutomationActionTarget internal raffleTarget;

    function setUp() public {
        registry = new ProtocolRegistry(admin);
        forwarder = new AutomationForwarderMock();
        receiver = new ProtocolAutomationReceiver(admin, address(forwarder), address(registry), CHAIN_SELECTOR);

        openTarget = new AutomationActionTarget();
        blindTarget = new AutomationActionTarget();
        dutchTarget = new AutomationActionTarget();
        marketplaceTarget = new AutomationActionTarget();
        raffleTarget = new AutomationActionTarget();

        vm.startPrank(admin);
        registry.registerInstance(address(openTarget), seller, address(0), keccak256("OPEN_AUCTION"), 1);
        registry.registerInstance(address(blindTarget), seller, address(0), keccak256("BLIND_AUCTION"), 1);
        registry.registerInstance(address(dutchTarget), seller, address(0), keccak256("DUTCH_AUCTION"), 1);
        registry.registerInstance(address(marketplaceTarget), seller, address(0), keccak256("MARKETPLACE"), 1);
        registry.registerInstance(address(raffleTarget), seller, address(0), keccak256("RAFFLE"), 1);
        receiver.setExpectedWorkflowId(WORKFLOW_ID);
        receiver.setExpectedAuthor(workflowAuthor);
        receiver.unpauseAutomation();
        vm.stopPrank();
    }

    function _metadata() internal view returns (bytes memory) {
        return abi.encodePacked(WORKFLOW_ID, bytes10(0), workflowAuthor, bytes2(0));
    }

    function _report(
        ProtocolAutomationReceiver.Action action,
        address instance,
        uint256 id,
        uint256 value,
        uint256 cursor
    ) internal view returns (bytes memory) {
        return abi.encode(action, instance, id, value, cursor, uint64(block.timestamp), CHAIN_SELECTOR);
    }

    function _deliver(bytes memory report) internal {
        vm.prank(address(forwarder));
        receiver.onReport(_metadata(), report);
    }

    function test_ReceiverStartsPausedAndRequiresWorkflowConfiguration() public {
        ProtocolAutomationReceiver fresh =
            new ProtocolAutomationReceiver(admin, address(forwarder), address(registry), CHAIN_SELECTOR);
        assertTrue(fresh.paused());
        vm.prank(admin);
        vm.expectRevert(ProtocolAutomationReceiver.WorkflowNotConfigured.selector);
        fresh.unpauseAutomation();
    }

    function test_RejectsNonForwarderAndWrongWorkflowIdentity() public {
        bytes memory report =
            _report(ProtocolAutomationReceiver.Action.FINALIZE_OPEN_AUCTION, address(openTarget), 1, 0, 0);
        vm.expectRevert(
            abi.encodeWithSelector(ReceiverTemplate.InvalidSender.selector, address(this), address(forwarder))
        );
        receiver.onReport(_metadata(), report);

        bytes32 otherId = keccak256("other-workflow");
        vm.prank(address(forwarder));
        vm.expectRevert(abi.encodeWithSelector(ReceiverTemplate.InvalidWorkflowId.selector, otherId, WORKFLOW_ID));
        receiver.onReport(abi.encodePacked(otherId, bytes10(0), workflowAuthor, bytes2(0)), report);

        address otherAuthor = makeAddr("other-author");
        vm.prank(address(forwarder));
        vm.expectRevert(abi.encodeWithSelector(ReceiverTemplate.InvalidAuthor.selector, otherAuthor, workflowAuthor));
        receiver.onReport(abi.encodePacked(WORKFLOW_ID, bytes10(0), otherAuthor, bytes2(0)), report);

        vm.prank(address(forwarder));
        vm.expectRevert();
        receiver.onReport(bytes("bad"), report);
    }

    function test_ProductionReceiverFailsClosedWhenIdentityIsClearedAfterUnpause() public {
        vm.startPrank(admin);
        receiver.setExpectedWorkflowId(bytes32(0));
        vm.stopPrank();

        vm.prank(address(forwarder));
        vm.expectRevert(ProtocolAutomationReceiver.WorkflowNotConfigured.selector);
        receiver.onReport(
            _metadata(), _report(ProtocolAutomationReceiver.Action.FINALIZE_OPEN_AUCTION, address(openTarget), 1, 0, 0)
        );
        assertFalse(receiver.workflowConfigured());
    }

    function test_ProductionReceiverFailsClosedWhenForwarderIsDisabled() public {
        vm.prank(admin);
        receiver.setForwarderAddress(address(0));
        vm.expectRevert(ProtocolAutomationReceiver.InvalidForwarder.selector);
        receiver.onReport(
            _metadata(), _report(ProtocolAutomationReceiver.Action.FINALIZE_OPEN_AUCTION, address(openTarget), 1, 0, 0)
        );
    }

    function test_ReceiverSupportsIReceiverAndERC165() public view {
        assertTrue(receiver.supportsInterface(type(IReceiver).interfaceId));
        assertTrue(receiver.supportsInterface(type(IERC165).interfaceId));
        assertFalse(receiver.supportsInterface(0xffffffff));
    }

    function test_OwnershipStaysTwoStep() public {
        address newOwner = makeAddr("new-owner");
        vm.prank(admin);
        receiver.transferOwnership(newOwner);
        assertEq(receiver.owner(), admin);
        assertEq(receiver.pendingOwner(), newOwner);
        vm.prank(newOwner);
        receiver.acceptOwnership();
        assertEq(receiver.owner(), newOwner);
    }

    function test_SimulationReceiverWorksWithoutMetadataAndNeverInProductionReceiver() public {
        ProtocolAutomationSimulationReceiver sim =
            new ProtocolAutomationSimulationReceiver(admin, address(forwarder), address(registry), CHAIN_SELECTOR);
        assertTrue(sim.paused());
        vm.prank(admin);
        sim.unpauseAutomation();
        assertFalse(sim.workflowConfigured());

        bytes memory report =
            _report(ProtocolAutomationReceiver.Action.FINALIZE_OPEN_AUCTION, address(openTarget), 3, 0, 0);
        vm.prank(address(forwarder));
        sim.onReport(new bytes(0), report);
        assertEq(openTarget.callCount(), 1);
        assertEq(openTarget.lastId(), 3);

        ProtocolAutomationReceiver prod =
            new ProtocolAutomationReceiver(admin, address(forwarder), address(registry), CHAIN_SELECTOR);
        vm.prank(admin);
        vm.expectRevert(ProtocolAutomationReceiver.WorkflowNotConfigured.selector);
        prod.unpauseAutomation();
    }

    function test_SimulationReceiverStillEnforcesChainSelectorKindAndReplay() public {
        ProtocolAutomationSimulationReceiver sim =
            new ProtocolAutomationSimulationReceiver(admin, address(forwarder), address(registry), CHAIN_SELECTOR);
        vm.prank(admin);
        sim.unpauseAutomation();

        vm.prank(address(forwarder));
        vm.expectRevert(ProtocolAutomationReceiver.InvalidChainSelector.selector);
        sim.onReport(
            new bytes(0),
            abi.encode(
                ProtocolAutomationReceiver.Action.FINALIZE_OPEN_AUCTION,
                address(openTarget),
                uint256(1),
                uint256(0),
                uint256(0),
                uint64(block.timestamp),
                uint64(1)
            )
        );

        bytes memory report =
            _report(ProtocolAutomationReceiver.Action.FINALIZE_OPEN_AUCTION, address(openTarget), 5, 0, 0);
        vm.prank(address(forwarder));
        sim.onReport(new bytes(0), report);
        vm.prank(address(forwarder));
        vm.expectRevert(ProtocolAutomationReceiver.ReplayOrStaleReport.selector);
        sim.onReport(new bytes(0), report);
    }

    function test_DispatchesKnownActionsAndBlocksReplay() public {
        _deliver(_report(ProtocolAutomationReceiver.Action.FINALIZE_OPEN_AUCTION, address(openTarget), 7, 0, 0));
        assertEq(openTarget.callCount(), 1);
        assertEq(openTarget.lastId(), 7);

        bytes memory report =
            _report(ProtocolAutomationReceiver.Action.EXPIRE_DUTCH_AUCTION, address(dutchTarget), 9, 0, 0);
        _deliver(report);
        assertEq(dutchTarget.callCount(), 1);
        assertEq(dutchTarget.lastId(), 9);

        vm.prank(address(forwarder));
        vm.expectRevert(ProtocolAutomationReceiver.ReplayOrStaleReport.selector);
        receiver.onReport(
            _metadata(), _report(ProtocolAutomationReceiver.Action.FINALIZE_OPEN_AUCTION, address(openTarget), 7, 0, 0)
        );
    }

    function test_RejectsWrongTargetKindAndInactiveTarget() public {
        bytes32 expectedKind = receiver.KIND_MARKETPLACE();
        bytes32 actualKind = receiver.KIND_OPEN_AUCTION();
        bytes memory meta = _metadata();
        bytes memory wrongKind = _report(ProtocolAutomationReceiver.Action.EXPIRE_OFFER, address(openTarget), 1, 0, 0);
        vm.prank(address(forwarder));
        vm.expectRevert(
            abi.encodeWithSelector(ProtocolAutomationReceiver.InvalidTargetKind.selector, expectedKind, actualKind)
        );
        receiver.onReport(meta, wrongKind);

        vm.prank(admin);
        registry.setActive(address(openTarget), false);
        bytes memory inactive =
            _report(ProtocolAutomationReceiver.Action.FINALIZE_OPEN_AUCTION, address(openTarget), 1, 0, 0);
        vm.prank(address(forwarder));
        vm.expectRevert(ProtocolAutomationReceiver.InactiveInstance.selector);
        receiver.onReport(meta, inactive);
    }

    function test_RefundAutomationRequiresExactCursorAndBoundedBatch() public {
        bytes memory wrongCursor =
            _report(ProtocolAutomationReceiver.Action.PROCESS_RAFFLE_REFUNDS, address(raffleTarget), 1, 100, 1);
        vm.prank(address(forwarder));
        vm.expectRevert(ProtocolAutomationReceiver.InvalidRefundCursor.selector);
        receiver.onReport(_metadata(), wrongCursor);

        bytes memory badBatch =
            _report(ProtocolAutomationReceiver.Action.PROCESS_RAFFLE_REFUNDS, address(raffleTarget), 1, 101, 0);
        vm.prank(address(forwarder));
        vm.expectRevert(ProtocolAutomationReceiver.InvalidRefundBatch.selector);
        receiver.onReport(_metadata(), badBatch);

        _deliver(_report(ProtocolAutomationReceiver.Action.PROCESS_RAFFLE_REFUNDS, address(raffleTarget), 1, 100, 0));
        assertEq(raffleTarget.callCount(), 1);
        assertEq(raffleTarget.lastValue(), 100);
        assertEq(raffleTarget.cursor(), 100);

        vm.prank(address(forwarder));
        vm.expectRevert(ProtocolAutomationReceiver.InvalidRefundCursor.selector);
        receiver.onReport(
            _metadata(),
            _report(ProtocolAutomationReceiver.Action.PROCESS_RAFFLE_REFUNDS, address(raffleTarget), 1, 100, 0)
        );
    }

    function test_PausingReceiverBlocksReports() public {
        vm.prank(admin);
        receiver.pauseAutomation();
        vm.prank(address(forwarder));
        vm.expectRevert(ProtocolAutomationReceiver.AutomationPaused.selector);
        receiver.onReport(
            _metadata(), _report(ProtocolAutomationReceiver.Action.FINALIZE_OPEN_AUCTION, address(openTarget), 1, 0, 0)
        );
    }
}

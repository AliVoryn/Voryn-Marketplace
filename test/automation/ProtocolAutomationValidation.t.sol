// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../support/AutomationIntegrationBase.sol";
import "../../src/automation/ProtocolAutomationSimulationReceiver.sol";

contract ProtocolAutomationValidationTest is AutomationIntegrationBase {
    function _raw(
        uint8 action,
        address instance,
        uint256 id,
        uint256 value,
        uint256 cursor,
        uint64 scheduledAt,
        uint64 selector
    ) internal pure returns (bytes memory) {
        return abi.encode(action, instance, id, value, cursor, scheduledAt, selector);
    }

    function _expectRevertOnReport(bytes memory report, bytes4 errorSelector) internal {
        bytes memory meta = _metadata();
        vm.prank(address(forwarder));
        vm.expectRevert(errorSelector);
        receiver.onReport(meta, report);
    }

    function _now() internal view returns (uint64) {
        return uint64(block.timestamp);
    }

    function test_ConstructorRejectsInvalidArguments() public {
        vm.expectRevert(abi.encodeWithSelector(bytes4(keccak256("OwnableInvalidOwner(address)")), address(0)));
        new ProtocolAutomationReceiver(address(0), address(forwarder), address(registry), CHAIN_SELECTOR);

        vm.expectRevert(ReceiverTemplate.InvalidForwarderAddress.selector);
        new ProtocolAutomationReceiver(admin, address(0), address(registry), CHAIN_SELECTOR);

        vm.expectRevert(ProtocolAutomationReceiver.InvalidForwarder.selector);
        new ProtocolAutomationReceiver(admin, makeAddr("eoa-forwarder"), address(registry), CHAIN_SELECTOR);

        vm.expectRevert(ProtocolAutomationReceiver.InvalidRegistry.selector);
        new ProtocolAutomationReceiver(admin, address(forwarder), address(0), CHAIN_SELECTOR);

        vm.expectRevert(ProtocolAutomationReceiver.InvalidRegistry.selector);
        new ProtocolAutomationReceiver(admin, address(forwarder), makeAddr("eoa-registry"), CHAIN_SELECTOR);

        vm.expectRevert(ProtocolAutomationReceiver.InvalidChainSelector.selector);
        new ProtocolAutomationReceiver(admin, address(forwarder), address(registry), 0);
    }

    function test_CurrentTimestampReportsBlockTime() public {
        vm.warp(1_234_567);
        assertEq(receiver.currentTimestamp(), 1_234_567);
    }

    function test_RejectsReportsWithWrongLength() public {
        _expectRevertOnReport(new bytes(0), ProtocolAutomationReceiver.InvalidReport.selector);
        _expectRevertOnReport(new bytes(192), ProtocolAutomationReceiver.InvalidReport.selector);
        _expectRevertOnReport(new bytes(256), ProtocolAutomationReceiver.InvalidReport.selector);
    }

    function test_RejectsUnknownActionCode() public {
        _expectRevertOnReport(
            _raw(7, address(openAuction), 1, 0, 0, _now(), CHAIN_SELECTOR),
            ProtocolAutomationReceiver.InvalidAction.selector
        );
        _expectRevertOnReport(
            _raw(255, address(openAuction), 1, 0, 0, _now(), CHAIN_SELECTOR),
            ProtocolAutomationReceiver.InvalidAction.selector
        );
    }

    function test_RejectsZeroAndCodelessInstances() public {
        _expectRevertOnReport(
            _raw(0, address(0), 1, 0, 0, _now(), CHAIN_SELECTOR), ProtocolAutomationReceiver.InvalidInstance.selector
        );
        _expectRevertOnReport(
            _raw(0, makeAddr("eoa"), 1, 0, 0, _now(), CHAIN_SELECTOR),
            ProtocolAutomationReceiver.InvalidInstance.selector
        );
    }

    function test_RejectsWrongChainSelector() public {
        _expectRevertOnReport(
            _raw(0, address(openAuction), 1, 0, 0, _now(), CHAIN_SELECTOR + 1),
            ProtocolAutomationReceiver.InvalidChainSelector.selector
        );
    }

    function test_RejectsZeroAndFarFutureSchedule() public {
        _expectRevertOnReport(
            _raw(0, address(openAuction), 1, 0, 0, 0, CHAIN_SELECTOR),
            ProtocolAutomationReceiver.InvalidSchedule.selector
        );
        uint64 tooFar = _now() + receiver.MAX_FUTURE_SKEW() + 1;
        _expectRevertOnReport(
            _raw(0, address(openAuction), 1, 0, 0, tooFar, CHAIN_SELECTOR),
            ProtocolAutomationReceiver.InvalidSchedule.selector
        );
    }

    function test_AcceptsScheduleAtTheSkewBoundaryAndInThePast() public {
        uint256 t1 = _mintApproved(seller, address(dutchAuction));
        uint256 t2 = _mintApproved(seller, address(dutchAuction));
        vm.startPrank(seller);
        uint256 id1 = dutchAuction.createAuction(address(nft), t1, 2 ether, 1 ether, 0, 1 days);
        uint256 id2 = dutchAuction.createAuction(address(nft), t2, 2 ether, 1 ether, 0, 1 days);
        vm.stopPrank();
        vm.warp(block.timestamp + 1 days);

        bytes memory meta = _metadata();
        uint64 boundary = _now() + receiver.MAX_FUTURE_SKEW();
        vm.prank(address(forwarder));
        receiver.onReport(meta, _raw(2, address(dutchAuction), id1, 0, 0, boundary, CHAIN_SELECTOR));
        vm.prank(address(forwarder));
        receiver.onReport(meta, _raw(2, address(dutchAuction), id2, 0, 0, 1, CHAIN_SELECTOR));
        assertEq(nft.ownerOf(t1), seller);
        assertEq(nft.ownerOf(t2), seller);
    }

    function test_RejectsInactiveInstance() public {
        vm.prank(admin);
        registry.setActive(address(openAuction), false);
        _expectRevertOnReport(
            _raw(0, address(openAuction), 1, 0, 0, _now(), CHAIN_SELECTOR),
            ProtocolAutomationReceiver.InactiveInstance.selector
        );
    }

    function test_BlindActionRequiresZeroId() public {
        _expectRevertOnReport(
            _raw(1, address(blindAuction), 1, 0, 0, _now(), CHAIN_SELECTOR),
            ProtocolAutomationReceiver.InvalidActionValue.selector
        );
    }

    function test_NonRefundActionsRequireIdAndZeroValueAndCursor() public {
        _expectRevertOnReport(
            _raw(0, address(openAuction), 0, 0, 0, _now(), CHAIN_SELECTOR),
            ProtocolAutomationReceiver.InvalidActionId.selector
        );
        _expectRevertOnReport(
            _raw(2, address(dutchAuction), 0, 0, 0, _now(), CHAIN_SELECTOR),
            ProtocolAutomationReceiver.InvalidActionId.selector
        );
        _expectRevertOnReport(
            _raw(3, address(marketplace), 0, 0, 0, _now(), CHAIN_SELECTOR),
            ProtocolAutomationReceiver.InvalidActionId.selector
        );
        _expectRevertOnReport(
            _raw(4, address(raffle), 0, 0, 0, _now(), CHAIN_SELECTOR),
            ProtocolAutomationReceiver.InvalidActionId.selector
        );
        _expectRevertOnReport(
            _raw(6, address(raffle), 0, 0, 0, _now(), CHAIN_SELECTOR),
            ProtocolAutomationReceiver.InvalidActionId.selector
        );
        _expectRevertOnReport(
            _raw(0, address(openAuction), 1, 1, 0, _now(), CHAIN_SELECTOR),
            ProtocolAutomationReceiver.InvalidActionValue.selector
        );
        _expectRevertOnReport(
            _raw(0, address(openAuction), 1, 0, 1, _now(), CHAIN_SELECTOR),
            ProtocolAutomationReceiver.InvalidActionValue.selector
        );
        _expectRevertOnReport(
            _raw(1, address(blindAuction), 0, 1, 0, _now(), CHAIN_SELECTOR),
            ProtocolAutomationReceiver.InvalidActionValue.selector
        );
    }

    function test_RefundActionRequiresIdBatchAndCursor() public {
        _expectRevertOnReport(
            _raw(5, address(raffle), 0, 10, 0, _now(), CHAIN_SELECTOR),
            ProtocolAutomationReceiver.InvalidActionId.selector
        );
        _expectRevertOnReport(
            _raw(5, address(raffle), 1, 0, 0, _now(), CHAIN_SELECTOR),
            ProtocolAutomationReceiver.InvalidRefundBatch.selector
        );
        _expectRevertOnReport(
            _raw(5, address(raffle), 1, 101, 0, _now(), CHAIN_SELECTOR),
            ProtocolAutomationReceiver.InvalidRefundBatch.selector
        );
        _expectRevertOnReport(
            _raw(5, address(raffle), 1, 10, 3, _now(), CHAIN_SELECTOR),
            ProtocolAutomationReceiver.InvalidRefundCursor.selector
        );
    }

    function test_SameReportCannotBeReplayedEvenAfterTimePasses() public {
        uint256 tokenId = _mintApproved(seller, address(dutchAuction));
        vm.prank(seller);
        uint256 id = dutchAuction.createAuction(address(nft), tokenId, 2 ether, 1 ether, 0, 1 days);
        vm.warp(block.timestamp + 1 days);
        _deliver(ProtocolAutomationReceiver.Action.EXPIRE_DUTCH_AUCTION, address(dutchAuction), id, 0, 0);
        vm.warp(block.timestamp + 1 hours);
        _expectRevertOnReport(
            _raw(2, address(dutchAuction), id, 0, 0, _now(), CHAIN_SELECTOR),
            ProtocolAutomationReceiver.ReplayOrStaleReport.selector
        );
    }

    function test_FailedDomainCallRevertsWholeReportAndAllowsALaterRetry() public {
        uint256 tokenId = _mintApproved(seller, address(dutchAuction));
        vm.prank(seller);
        uint256 id = dutchAuction.createAuction(address(nft), tokenId, 2 ether, 1 ether, 0, 1 days);
        bytes memory meta = _metadata();
        bytes memory report =
            _encode(ProtocolAutomationReceiver.Action.EXPIRE_DUTCH_AUCTION, address(dutchAuction), id, 0, 0);
        vm.prank(address(forwarder));
        vm.expectRevert(IDutchAuction.InvalidTime.selector);
        receiver.onReport(meta, report);
        assertFalse(
            receiver.processedOperations(
                keccak256(
                    abi.encode(
                        ProtocolAutomationReceiver.Action.EXPIRE_DUTCH_AUCTION,
                        address(dutchAuction),
                        id,
                        uint256(0),
                        uint256(0)
                    )
                )
            )
        );
        vm.warp(block.timestamp + 1 days);
        vm.prank(address(forwarder));
        receiver.onReport(
            meta, _encode(ProtocolAutomationReceiver.Action.EXPIRE_DUTCH_AUCTION, address(dutchAuction), id, 0, 0)
        );
        assertEq(nft.ownerOf(tokenId), seller);
    }

    function test_PausedReceiverRejectsEvenValidReports() public {
        vm.prank(admin);
        receiver.pauseAutomation();
        _expectRevertOnReport(
            _raw(1, address(blindAuction), 0, 0, 0, _now(), CHAIN_SELECTOR),
            ProtocolAutomationReceiver.AutomationPaused.selector
        );
    }
}


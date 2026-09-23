// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../support/AutomationIntegrationBase.sol";

contract ProtocolAutomationIntegrationTest is AutomationIntegrationBase {
    uint256 internal constant SCAN = 250;
    uint256 internal constant ITEMS = 25;

    function _cycleFor(bytes32 kind, uint256 offset) internal view returns (address instance, uint256 cycle) {
        (address[] memory instances, uint256 c) = registry.automationInstancesWithCycle(kind, offset, 1);
        assertEq(instances.length, 1);
        return (instances[0], c);
    }

    function test_FinalizeOpenAuctionThroughReceiver() public {
        uint256 tokenId = _mintApproved(seller, address(openAuction));
        vm.prank(seller);
        uint256 auctionId = openAuction.createAuction(address(nft), tokenId, 1 ether, 0.1 ether, 0, 1 days);
        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        openAuction.placeBid{ value: 1 ether }(auctionId);

        (address instance, uint256 cycle) = _cycleFor(keccak256("OPEN_AUCTION"), 0);
        assertEq(instance, address(openAuction));
        assertEq(openAuction.automationDueIds(cycle, SCAN, ITEMS).length, 0);

        vm.warp(block.timestamp + 1 days + 1);
        uint256[] memory due = openAuction.automationDueIds(cycle, SCAN, ITEMS);
        assertEq(due.length, 1);
        assertEq(due[0], auctionId);

        _deliver(ProtocolAutomationReceiver.Action.FINALIZE_OPEN_AUCTION, instance, due[0], 0, 0);

        assertEq(nft.ownerOf(tokenId), buyer);
        assertEq(treasury.claimable(seller), 0.975 ether);
        assertEq(openAuction.automationDueIds(cycle, SCAN, ITEMS).length, 0);
    }

    function test_FinalizeBlindAuctionThroughReceiver() public {
        bytes32 secret = keccak256("secret");
        bytes32 commitment = blindAuction.computeBlindedBid(2 ether, false, secret);
        vm.deal(buyer, 2 ether);
        vm.prank(buyer);
        blindAuction.placeBid{ value: 2 ether }(commitment);

        vm.warp(block.timestamp + BLIND_BIDDING_TIME + 1);
        uint256[] memory values = new uint256[](1);
        values[0] = 2 ether;
        bool[] memory fakes = new bool[](1);
        bytes32[] memory secrets = new bytes32[](1);
        secrets[0] = secret;
        vm.prank(buyer);
        blindAuction.reveal(values, fakes, secrets);

        assertFalse(blindAuction.automationReady());
        vm.warp(block.timestamp + BLIND_REVEAL_TIME + 1);
        assertTrue(blindAuction.automationReady());

        _deliver(ProtocolAutomationReceiver.Action.FINALIZE_BLIND_AUCTION, address(blindAuction), 0, 0, 0);

        assertEq(nft.ownerOf(blindAuction.tokenId()), buyer);
        assertTrue(blindAuction.auctionEnded());
        assertFalse(blindAuction.automationReady());
    }

    function test_ExpireDutchAuctionThroughReceiver() public {
        uint256 tokenId = _mintApproved(seller, address(dutchAuction));
        vm.prank(seller);
        uint256 id = dutchAuction.createAuction(address(nft), tokenId, 2 ether, 1 ether, 0, 1 days);

        (address instance, uint256 cycle) = _cycleFor(keccak256("DUTCH_AUCTION"), 0);
        assertEq(dutchAuction.automationDueIds(cycle, SCAN, ITEMS).length, 0);

        vm.warp(block.timestamp + 1 days);
        uint256[] memory due = dutchAuction.automationDueIds(cycle, SCAN, ITEMS);
        assertEq(due.length, 1);
        assertEq(due[0], id);

        _deliver(ProtocolAutomationReceiver.Action.EXPIRE_DUTCH_AUCTION, instance, due[0], 0, 0);

        assertEq(nft.ownerOf(tokenId), seller);
        assertEq(uint8(dutchAuction.getAuction(id).status), uint8(IDutchAuction.AuctionStatus.Expired));
        assertEq(dutchAuction.automationDueIds(cycle, SCAN, ITEMS).length, 0);
    }

    function test_ExpireOfferThroughReceiver() public {
        uint256 tokenId = _mint(nft, seller);
        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        uint256 offerId =
            marketplace.makeOffer{ value: 1 ether }(address(nft), tokenId, uint64(block.timestamp + 1 days));

        (address instance, uint256 cycle) = _cycleFor(keccak256("MARKETPLACE"), 0);
        assertEq(marketplace.automationDueOfferIds(cycle, SCAN, ITEMS).length, 0);

        vm.warp(block.timestamp + 1 days);
        uint256[] memory due = marketplace.automationDueOfferIds(cycle, SCAN, ITEMS);
        assertEq(due.length, 1);
        assertEq(due[0], offerId);

        _deliver(ProtocolAutomationReceiver.Action.EXPIRE_OFFER, instance, due[0], 0, 0);

        assertEq(marketplace.totalOfferEscrow(), 0);
        assertEq(paymentManager.claimable(buyer), 1 ether);
        assertEq(marketplace.automationDueOfferIds(cycle, SCAN, ITEMS).length, 0);
    }

    function test_RequestRaffleWinnerThroughReceiver() public {
        uint256 tokenId = _mintApproved(seller, address(raffle));
        vm.prank(seller);
        uint256 id = raffle.createRaffle(address(nft), tokenId, 1 ether, 10, 10, 0, 1 days);
        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        raffle.buyTickets{ value: 1 ether }(id, 1);

        (address instance, uint256 cycle) = _cycleFor(keccak256("RAFFLE"), 0);
        (uint256[] memory winners,,) = raffle.automationCandidates(cycle, SCAN, ITEMS);
        assertEq(winners.length, 0);

        vm.warp(block.timestamp + 1 days);
        (winners,,) = raffle.automationCandidates(cycle, SCAN, ITEMS);
        assertEq(winners.length, 1);
        assertEq(winners[0], id);

        _deliver(ProtocolAutomationReceiver.Action.REQUEST_RAFFLE_WINNER, instance, winners[0], 0, 0);

        assertEq(uint8(raffle.getRaffle(id).phase), uint8(IRaffle.RafflePhase.AwaitingRandomness));
        assertEq(raffle.getRaffle(id).vrfRequestId, 1);
    }

    function test_FinalizeFailedRaffleThroughReceiver() public {
        uint256 tokenId = _mintApproved(seller, address(raffle));
        vm.prank(seller);
        uint256 id = raffle.createRaffle(address(nft), tokenId, 1 ether, 10, 10, 0, 1 days);

        (address instance, uint256 cycle) = _cycleFor(keccak256("RAFFLE"), 0);
        vm.warp(block.timestamp + 1 days);
        (, uint256[] memory failed,) = raffle.automationCandidates(cycle, SCAN, ITEMS);
        assertEq(failed.length, 1);
        assertEq(failed[0], id);

        _deliver(ProtocolAutomationReceiver.Action.FINALIZE_FAILED_RAFFLE, instance, failed[0], 0, 0);

        assertEq(uint8(raffle.getRaffle(id).phase), uint8(IRaffle.RafflePhase.Failed));
        assertEq(nft.ownerOf(tokenId), seller);
    }

    function test_ProcessRaffleRefundsThroughReceiverAdvancesTheCursor() public {
        uint256 tokenId = _mintApproved(seller, address(raffle));
        vm.prank(seller);
        uint256 id = raffle.createRaffle(address(nft), tokenId, 0.1 ether, 10, 10, 0, 1 days);
        address[3] memory buyers = [makeAddr("b1"), makeAddr("b2"), makeAddr("b3")];
        for (uint256 i = 0; i < buyers.length; ++i) {
            vm.deal(buyers[i], 0.1 ether);
            vm.prank(buyers[i]);
            raffle.buyTickets{ value: 0.1 ether }(id, 1);
        }
        (address instance, uint256 cycle) = _cycleFor(keccak256("RAFFLE"), 0);

        vm.warp(block.timestamp + 1 days);
        _deliver(ProtocolAutomationReceiver.Action.REQUEST_RAFFLE_WINNER, instance, id, 0, 0);
        vm.warp(block.timestamp + raffle.STUCK_RAFFLE_CANCEL_DELAY());
        vm.prank(seller);
        raffle.cancelStuckRaffle(id);

        (,, Raffle.AutomationRefundCandidate[] memory refunds) = raffle.automationCandidates(cycle, SCAN, ITEMS);
        assertEq(refunds.length, 1);
        assertEq(refunds[0].raffleId, id);
        assertEq(refunds[0].cursor, 0);

        _deliver(ProtocolAutomationReceiver.Action.PROCESS_RAFFLE_REFUNDS, instance, id, 2, refunds[0].cursor);
        assertEq(raffle.refundCursor(id), 2);
        assertEq(raffle.raffleRefunds(buyers[0]), 0.1 ether);
        assertEq(raffle.raffleRefunds(buyers[1]), 0.1 ether);
        assertEq(raffle.raffleRefunds(buyers[2]), 0);

        (,, refunds) = raffle.automationCandidates(cycle, SCAN, ITEMS);
        assertEq(refunds.length, 1);
        assertEq(refunds[0].cursor, 2);

        vm.prank(address(forwarder));
        vm.expectRevert(ProtocolAutomationReceiver.InvalidRefundCursor.selector);
        receiver.onReport(
            _metadata(), _encode(ProtocolAutomationReceiver.Action.PROCESS_RAFFLE_REFUNDS, instance, id, 2, 0)
        );

        _deliver(ProtocolAutomationReceiver.Action.PROCESS_RAFFLE_REFUNDS, instance, id, 2, refunds[0].cursor);
        assertEq(raffle.refundCursor(id), 3);
        assertEq(raffle.raffleRefunds(buyers[2]), 0.1 ether);
        (,, refunds) = raffle.automationCandidates(cycle, SCAN, ITEMS);
        assertEq(refunds.length, 0);
    }

    function test_ReceiverRejectsActionAimedAtWrongRealContract() public {
        bytes32 expectedKind = receiver.KIND_MARKETPLACE();
        bytes32 actualKind = receiver.KIND_RAFFLE();
        bytes memory meta = _metadata();
        bytes memory report = _encode(ProtocolAutomationReceiver.Action.EXPIRE_OFFER, address(raffle), 1, 0, 0);
        vm.prank(address(forwarder));
        vm.expectRevert(
            abi.encodeWithSelector(ProtocolAutomationReceiver.InvalidTargetKind.selector, expectedKind, actualKind)
        );
        receiver.onReport(meta, report);
    }
}


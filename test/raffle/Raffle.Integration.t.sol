// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../support/TestBase.sol";

contract RaffleIntegrationTest is ProtocolTestBase {
    Raffle internal raffle;
    MockVRFCoordinatorV2Plus internal coordinator;
    uint256 internal tokenId;

    function setUp() public {
        _setUpCore();
        coordinator = _deployMockCoordinator();
        raffle = _deployRaffle(address(treasury), coordinator);
        tokenId = _mint(nft, seller);
        vm.prank(seller);
        nft.approve(address(raffle), tokenId);
        vm.prank(admin);
        treasury.setAuthorizedPayer(address(raffle), true);
    }

    function test_RafflePurchaseFlowsIntoVRFReadyProtocolState() public {
        vm.prank(seller);
        uint256 id = raffle.createRaffle(address(nft), tokenId, 1 ether, 2, 2, 0, 1 days);
        vm.deal(buyer, 2 ether);
        vm.prank(buyer);
        raffle.buyTickets{ value: 2 ether }(id, 2);
        assertEq(raffle.ticketsOwnedBy(id, buyer), 2);
        assertEq(raffle.entrantCount(id), 1);
        assertEq(uint8(raffle.getRaffle(id).phase), uint8(IRaffle.RafflePhase.AwaitingRandomness));
        assertEq(raffle.getRaffle(id).vrfRequestId, 1);
        vm.prank(seller);
        vm.expectRevert(IRaffle.InvalidPhase.selector);
        raffle.requestRandomWinner(id);
        coordinator.fulfillSingle(1, 7);
        assertEq(uint8(raffle.getRaffle(id).phase), uint8(IRaffle.RafflePhase.Finalized));
        assertEq(nft.ownerOf(tokenId), buyer);
        assertEq(treasury.claimable(feeRecipient), 0.05 ether);
        assertEq(treasury.claimable(seller), 1.95 ether);
        assertEq(raffle.totalActiveRaffleFunds(), 0);
    }

    function test_CancelledRaffleRefundPipelineConservesBuyerClaim() public {
        vm.prank(seller);
        uint256 id = raffle.createRaffle(address(nft), tokenId, 1 ether, 10, 10, 0, 1 days);
        vm.deal(buyer, 2 ether);
        vm.prank(buyer);
        raffle.buyTickets{ value: 2 ether }(id, 2);
        vm.prank(seller);
        vm.expectRevert(IRaffle.TicketsAlreadySold.selector);
        raffle.cancelRaffle(id);
    }

    function test_CancelledRaffleRefundsAllEntrantsThroughCursor() public {
        vm.prank(seller);
        uint256 id = raffle.createRaffle(address(nft), tokenId, 0.1 ether, 10, 10, 0, 1 days);
        vm.deal(buyer, 0.2 ether);
        vm.prank(buyer);
        raffle.buyTickets{ value: 0.1 ether }(id, 1);
        vm.prank(buyer2);
        vm.deal(buyer2, 0.1 ether);
        raffle.buyTickets{ value: 0.1 ether }(id, 1);
        vm.warp(block.timestamp + 1 days);
        raffle.requestRandomWinner(id);
        vm.warp(block.timestamp + raffle.STUCK_RAFFLE_CANCEL_DELAY());
        vm.prank(seller);
        raffle.cancelStuckRaffle(id);

        vm.prank(buyer);
        raffle.processRaffleRefunds(id, 1);
        assertEq(raffle.refundCursor(id), 1);
        assertEq(raffle.raffleRefunds(buyer), 0.1 ether);
        assertEq(raffle.totalRaffleRefundLiability(), 0.1 ether);

        vm.prank(buyer2);
        raffle.processRaffleRefunds(id, 1);
        assertEq(raffle.refundCursor(id), 2);
        assertEq(raffle.raffleRefunds(buyer2), 0.1 ether);
        assertEq(raffle.totalActiveRaffleFunds(), 0);
        assertEq(raffle.totalRaffleRefundLiability(), 0.2 ether);

        vm.prank(buyer);
        raffle.claimRaffleRefund();
        vm.prank(buyer2);
        raffle.claimRaffleRefund();
        assertEq(raffle.totalRaffleRefundLiability(), 0);
        assertEq(address(raffle).balance, 0);
    }

    function test_FulfillmentGasStaysWithinTheRecommendedCallbackLimit() public {
        vm.prank(seller);
        uint256 id = raffle.createRaffle(address(nft), tokenId, 1 ether, 6, 6, 0, 1 days);
        address[3] memory participants = [buyer, buyer2, attacker];
        for (uint256 i; i < participants.length; ++i) {
            vm.deal(participants[i], 2 ether);
            vm.prank(participants[i]);
            raffle.buyTickets{ value: 2 ether }(id, 2);
        }
        assertEq(uint8(raffle.getRaffle(id).phase), uint8(IRaffle.RafflePhase.AwaitingRandomness));
        uint256 gasBefore = gasleft();
        coordinator.fulfillSingle(1, 11);
        uint256 gasUsed = gasBefore - gasleft();
        emit log_named_uint("raffle fulfillment gas", gasUsed);
        assertLt(gasUsed, 500_000);
        assertEq(uint8(raffle.getRaffle(id).phase), uint8(IRaffle.RafflePhase.Finalized));
    }
}

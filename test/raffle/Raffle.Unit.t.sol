// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../support/TestBase.sol";

contract RaffleUnitTest is ProtocolTestBase {
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
    }

    function test_CreateRaffleRecordsConfiguredLimits() public {
        vm.prank(seller);
        uint256 id = raffle.createRaffle(address(nft), tokenId, 0.1 ether, 100, 5, 0, 1 days);
        IRaffle.RaffleData memory data = raffle.getRaffle(id);
        assertEq(data.ticketPrice, 0.1 ether);
        assertEq(data.maxTickets, 100);
        assertEq(data.maxTicketsPerWallet, 5);
        assertEq(uint8(data.phase), uint8(IRaffle.RafflePhase.Active));
    }

    function test_ZeroMaxTicketsMeansNoGlobalCap() public {
        vm.prank(seller);
        uint256 id = raffle.createRaffle(address(nft), tokenId, 0.1 ether, 0, 0, 0, 1 days);
        vm.deal(buyer, 2 ether);
        vm.prank(buyer);
        raffle.buyTickets{ value: 2 ether }(id, 20);
        assertEq(raffle.ticketsOwnedBy(id, buyer), 20);
    }

    function test_FailedRaffleReturnsNFTWhenNoTicketsSold() public {
        vm.prank(seller);
        uint256 id = raffle.createRaffle(address(nft), tokenId, 0.1 ether, 10, 5, 0, 1 days);
        vm.warp(block.timestamp + 1 days);
        raffle.finalizeFailedRaffle(id);
        assertEq(nft.ownerOf(tokenId), seller);
    }

    function test_CreateRaffle_RejectsNonContractNFTAndPastStart() public {
        vm.prank(seller);
        vm.expectRevert(IRaffle.UnsupportedAsset.selector);
        raffle.createRaffle(address(0xBEEF), tokenId, 0.1 ether, 10, 0, 0, 1 days);
        vm.warp(block.timestamp + 1);
        vm.prank(seller);
        vm.expectRevert(IRaffle.InvalidTime.selector);
        raffle.createRaffle(address(nft), tokenId, 0.1 ether, 10, 0, uint64(block.timestamp - 1), 1 days);
    }

    function test_ScheduledRaffle_ActivatesOnFirstPurchaseAfterStart() public {
        uint64 startAt = uint64(block.timestamp + 1 hours);
        vm.prank(seller);
        uint256 id = raffle.createRaffle(address(nft), tokenId, 0.1 ether, 10, 0, startAt, 1 days);
        assertEq(uint8(raffle.getRaffle(id).phase), uint8(IRaffle.RafflePhase.Created));
        vm.warp(startAt);
        vm.deal(buyer, 0.1 ether);
        vm.prank(buyer);
        raffle.buyTickets{ value: 0.1 ether }(id, 1);
        assertEq(uint8(raffle.getRaffle(id).phase), uint8(IRaffle.RafflePhase.Active));
        assertEq(raffle.getRaffle(id).ticketsSold, 1);
    }

    function test_CancelRaffle_FromScheduledPhaseReturnsNFT() public {
        uint64 startAt = uint64(block.timestamp + 1 hours);
        vm.prank(seller);
        uint256 id = raffle.createRaffle(address(nft), tokenId, 0.1 ether, 10, 0, startAt, 1 days);
        vm.prank(seller);
        raffle.cancelRaffle(id);
        assertEq(uint8(raffle.getRaffle(id).phase), uint8(IRaffle.RafflePhase.Cancelled));
        assertEq(nft.ownerOf(tokenId), seller);
    }

    function test_FinalizeFailedRaffle_FromScheduledPhaseAfterEnd() public {
        uint64 startAt = uint64(block.timestamp + 1 hours);
        vm.prank(seller);
        uint256 id = raffle.createRaffle(address(nft), tokenId, 0.1 ether, 10, 0, startAt, 1 days);
        vm.warp(startAt + 1 days);
        raffle.finalizeFailedRaffle(id);
        assertEq(uint8(raffle.getRaffle(id).phase), uint8(IRaffle.RafflePhase.Failed));
        assertEq(nft.ownerOf(tokenId), seller);
    }

    function test_BuyTickets_RevertsWhenPriceTimesQuantityOverflows() public {
        uint256 hugePrice = type(uint256).max / 2 + 1;
        vm.prank(seller);
        uint256 id = raffle.createRaffle(address(nft), tokenId, hugePrice, 0, 0, 0, 1 days);
        vm.prank(buyer);
        vm.expectRevert(IRaffle.IncorrectPayment.selector);
        raffle.buyTickets(id, 2);
    }

    function test_Finalize_WithZeroFeeCreditsFullProceedsToCreator() public {
        vm.prank(admin);
        treasury.setAuthorizedPayer(address(raffle), true);
        vm.prank(admin);
        raffle.setFeeBps(0);
        vm.prank(seller);
        uint256 id = raffle.createRaffle(address(nft), tokenId, 0.1 ether, 2, 2, 0, 1 days);
        vm.deal(buyer, 0.2 ether);
        vm.prank(buyer);
        raffle.buyTickets{ value: 0.2 ether }(id, 2);
        coordinator.fulfillSingle(1, 3);
        assertEq(treasury.claimable(seller), 0.2 ether);
        assertEq(treasury.claimable(feeRecipient), 0);
        assertEq(nft.ownerOf(tokenId), buyer);
    }

    function test_EntrantViewsAndRaffleCount() public {
        assertEq(raffle.raffleCount(), 0);
        vm.prank(seller);
        uint256 id = raffle.createRaffle(address(nft), tokenId, 0.1 ether, 10, 0, 0, 1 days);
        assertEq(raffle.raffleCount(), 1);
        vm.deal(buyer, 0.2 ether);
        vm.prank(buyer);
        raffle.buyTickets{ value: 0.2 ether }(id, 2);
        vm.deal(buyer2, 0.3 ether);
        vm.prank(buyer2);
        raffle.buyTickets{ value: 0.3 ether }(id, 3);
        assertEq(raffle.entrantCount(id), 2);
        IRaffle.Entrant memory first = raffle.entrantAt(id, 0);
        IRaffle.Entrant memory second = raffle.entrantAt(id, 1);
        assertEq(first.buyer, buyer);
        assertEq(first.startIndex, 0);
        assertEq(first.ticketCount, 2);
        assertEq(second.buyer, buyer2);
        assertEq(second.startIndex, 2);
        assertEq(second.ticketCount, 3);
        vm.expectRevert();
        raffle.entrantAt(id, 2);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../support/TestBase.sol";

contract RaffleFuzzTest is ProtocolTestBase {
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

    function testFuzz_BuyTicketsRecordsExactQuantity(uint8 rawQuantity) public {
        uint256 quantity = bound(uint256(rawQuantity), 1, 20);
        vm.prank(seller);
        uint256 id = raffle.createRaffle(address(nft), tokenId, 0.1 ether, 100, 100, 0, 1 days);
        vm.deal(buyer, quantity * 0.1 ether);
        vm.prank(buyer);
        raffle.buyTickets{ value: quantity * 0.1 ether }(id, quantity);
        assertEq(raffle.ticketsOwnedBy(id, buyer), quantity);
        assertEq(raffle.getRaffle(id).ticketsSold, quantity);
    }

    function testFuzz_SoldOutRaffleRejectsFurtherPurchases(uint8 rawQuantity) public {
        uint256 maxTickets = bound(uint256(rawQuantity), 1, 20);
        vm.prank(seller);
        uint256 id = raffle.createRaffle(address(nft), tokenId, 0.1 ether, maxTickets, maxTickets, 0, 1 days);
        vm.deal(buyer, (maxTickets + 1) * 0.1 ether);
        vm.prank(buyer);
        raffle.buyTickets{ value: maxTickets * 0.1 ether }(id, maxTickets);
        vm.prank(buyer);
        vm.expectRevert(IRaffle.InvalidPhase.selector);
        raffle.buyTickets{ value: 0.1 ether }(id, 1);
        assertEq(raffle.getRaffle(id).ticketsSold, maxTickets);
    }

    function testFuzz_TicketAccountingMatchesPrice(uint96 rawPrice, uint8 rawQuantity) public {
        uint256 price = bound(uint256(rawPrice), 1, 2 ether);
        uint256 quantity = bound(uint256(rawQuantity), 1, 20);
        vm.prank(seller);
        uint256 id = raffle.createRaffle(address(nft), tokenId, price, 100, 100, 0, 1 days);
        vm.deal(buyer, price * quantity);
        vm.prank(buyer);
        raffle.buyTickets{ value: price * quantity }(id, quantity);
        assertEq(raffle.getRaffle(id).ticketsSold, quantity);
        assertEq(raffle.ticketsOwnedBy(id, buyer), quantity);
        assertEq(raffle.totalActiveRaffleFunds(), price * quantity);
    }

    function testFuzz_WrongPaymentAlwaysReverts(uint96 rawPrice, uint8 rawQuantity) public {
        uint256 price = bound(uint256(rawPrice), 1 ether, 2 ether);
        uint256 quantity = bound(uint256(rawQuantity), 1, 5);
        vm.prank(seller);
        uint256 id = raffle.createRaffle(address(nft), tokenId, price, 10, 10, 0, 1 days);
        vm.deal(buyer, price * quantity);
        vm.prank(buyer);
        vm.expectRevert(IRaffle.IncorrectPayment.selector);
        raffle.buyTickets{ value: price * quantity - 1 }(id, quantity);
    }

    function testFuzz_VRFConfirmationBounds(uint8 rawConfirmations) public {
        uint256 confirmations = bound(uint256(rawConfirmations), 0, 255);
        if (confirmations < 3 || confirmations > 200) {
            vm.prank(admin);
            vm.expectRevert(IRaffle.InvalidVRFConfig.selector);
            raffle.setVRFConfig(address(coordinator), 1, bytes32(uint256(1)), 200_000, uint16(confirmations), false);
            return;
        }
        vm.prank(admin);
        raffle.setVRFConfig(address(coordinator), 1, bytes32(uint256(1)), 200_000, uint16(confirmations), false);
        assertEq(raffle.requestConfirmations(), confirmations);
    }

    function testFuzz_CreateRaffleRejectsTimestampOverflow(uint64 rawStartAt) public {
        uint64 startAt = uint64(bound(uint256(rawStartAt), uint256(type(uint64).max) - 1023, uint256(type(uint64).max)));
        uint256 remaining = type(uint64).max - uint256(startAt);
        uint64 duration = uint64(remaining + 1);
        vm.prank(seller);
        vm.expectRevert(IRaffle.InvalidTime.selector);
        raffle.createRaffle(address(nft), tokenId, 0.1 ether, 10, 10, startAt, duration);
    }
}

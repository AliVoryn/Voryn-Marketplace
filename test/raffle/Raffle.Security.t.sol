// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import "../support/TestBase.sol";

contract RaffleSecurityTest is ProtocolTestBase {
    Raffle internal raffle;
    MockVRFCoordinatorV2Plus internal coordinator;
    uint256 internal tokenId;

    function setUp() public {
        _setUpCore();
        coordinator = _deployMockCoordinator();
        raffle = _deployRaffle(address(treasury), coordinator);
        vm.prank(admin);
        treasury.setAuthorizedPayer(address(raffle), true);
        tokenId = _mint(nft, seller);
        vm.prank(seller);
        nft.approve(address(raffle), tokenId);
    }

    function _create() internal returns (uint256 raffleId) {
        vm.prank(seller);
        raffleId = raffle.createRaffle(address(nft), tokenId, 0.1 ether, 10, 0, 0, 1 days);
    }

    function test_CreateRaffle_RevertsIfCallerDoesNotOwnToken() public {
        vm.prank(attacker);
        vm.expectRevert(IRaffle.NotCreator.selector);
        raffle.createRaffle(address(nft), tokenId, 0.1 ether, 10, 0, 0, 1 days);
    }

    function test_CreateRaffle_RejectsInvalidBoundaries() public {
        vm.prank(seller);
        vm.expectRevert(IRaffle.ZeroAddress.selector);
        raffle.createRaffle(address(0), tokenId, 0.1 ether, 10, 0, 0, 1 days);
        vm.prank(seller);
        vm.expectRevert(IRaffle.InvalidTicketPrice.selector);
        raffle.createRaffle(address(nft), tokenId, 0, 10, 0, 0, 1 days);
        vm.prank(seller);
        vm.expectRevert(IRaffle.InvalidTime.selector);
        raffle.createRaffle(address(nft), tokenId, 0.1 ether, 10, 0, 0, 0);
        vm.prank(seller);
        vm.expectRevert(IRaffle.InvalidMaxTickets.selector);
        raffle.createRaffle(address(nft), tokenId, 0.1 ether, uint256(type(uint128).max) + 1, 0, 0, 1 days);
    }

    function test_RaffleRequestAndFinalizeFailedBoundaries() public {
        uint256 raffleId = _create();
        vm.expectRevert(IRaffle.RaffleNotYetEnded.selector);
        raffle.requestRandomWinner(raffleId);
        vm.warp(block.timestamp + 1 days);
        vm.expectRevert(IRaffle.NoTicketsSold.selector);
        raffle.requestRandomWinner(raffleId);

        uint256 failedId = _createSecond();
        vm.warp(block.timestamp + 1 days);
        raffle.finalizeFailedRaffle(failedId);
        assertEq(uint8(raffle.getRaffle(failedId).phase), uint8(IRaffle.RafflePhase.Failed));
        assertEq(nft.ownerOf(raffle.getRaffle(failedId).tokenId), seller2);
    }

    function test_RandomnessRequestRequiresEndAndRetryDelay() public {
        uint256 raffleId = _create();
        vm.deal(buyer, 0.1 ether);
        vm.prank(buyer);
        raffle.buyTickets{ value: 0.1 ether }(raffleId, 1);
        vm.expectRevert(IRaffle.RaffleNotYetEnded.selector);
        raffle.requestRandomWinner(raffleId);
        vm.warp(block.timestamp + 1 days);
        raffle.requestRandomWinner(raffleId);
        vm.expectRevert(IRaffle.RandomnessNotYetDue.selector);
        vm.prank(admin);
        raffle.retryRandomWinnerRequest(raffleId);
        vm.warp(block.timestamp + 1 hours);
        vm.prank(admin);
        raffle.retryRandomWinnerRequest(raffleId);
        assertEq(raffle.getRaffle(raffleId).vrfRequestId, 2);
    }

    function test_CancelRaffle_OwnerCanCancelBeforeTickets() public {
        uint256 raffleId = _create();
        vm.prank(admin);
        raffle.cancelRaffle(raffleId);
        assertEq(uint8(raffle.getRaffle(raffleId).phase), uint8(IRaffle.RafflePhase.Cancelled));
        assertEq(nft.ownerOf(tokenId), seller);
    }

    function test_RaffleConfigurationAndUnknownViews() public {
        vm.expectRevert(IRaffle.RaffleNotFound.selector);
        raffle.getRaffle(999);
        assertEq(raffle.entrantCount(999), 0);
        vm.prank(attacker);
        vm.expectRevert();
        raffle.setFeeBps(100);
        vm.prank(admin);
        vm.expectRevert(IRaffle.InvalidFeeBps.selector);
        raffle.setFeeBps(1001);
        vm.prank(admin);
        vm.expectRevert(IRaffle.ZeroAddress.selector);
        raffle.setVRFConfig(address(0), 1, bytes32(0), 200_000, 3, false);
        vm.prank(admin);
        vm.expectRevert(IRaffle.InvalidVRFConfig.selector);
        raffle.setVRFConfig(address(coordinator), 1, bytes32(0), 200_000, 0, false);
        vm.prank(admin);
        raffle.setFeeBps(0);
        assertEq(raffle.feeBps(), 0);
    }

    function test_rawFulfillRandomWords_RevertsForNonCoordinatorCaller() public {
        uint256 raffleId = _create();
        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        raffle.buyTickets{ value: 1 ether }(raffleId, 10);
        uint256[] memory words = new uint256[](1);
        words[0] = 42;
        vm.prank(attacker);
        vm.expectRevert(IRaffle.OnlyCoordinatorCanFulfill.selector);
        raffle.rawFulfillRandomWords(1, words);
    }

    function test_MockCoordinator_FulfillsSingleWord() public {
        uint256 raffleId = _create();
        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        raffle.buyTickets{ value: 1 ether }(raffleId, 10);
        coordinator.fulfillSingle(1, 42);
        assertEq(uint8(raffle.getRaffle(raffleId).phase), uint8(IRaffle.RafflePhase.Finalized));
        assertTrue(coordinator.fulfilled(1));
    }

    function test_MockCoordinator_RejectsUnknownAndRepeatedRequests() public {
        uint256[] memory words = new uint256[](1);
        words[0] = 1;
        vm.expectRevert(bytes("unknown request"));
        coordinator.fulfill(999, words);

        uint256 raffleId = _create();
        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        raffle.buyTickets{ value: 1 ether }(raffleId, 10);
        coordinator.fulfillSingle(1, 7);
        vm.expectRevert(bytes("already fulfilled"));
        coordinator.fulfillSingle(1, 8);
        vm.expectRevert(bytes("already fulfilled"));
        coordinator.fulfill(1, words);
    }

    function test_CallbackUsesCoordinatorBoundToRequest() public {
        uint256 raffleId = _create();
        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        raffle.buyTickets{ value: 1 ether }(raffleId, 10);
        MockVRFCoordinatorV2Plus newCoordinator = new MockVRFCoordinatorV2Plus();
        vm.prank(admin);
        raffle.setVRFConfig(address(newCoordinator), 1, bytes32(uint256(2)), 200_000, 3, false);
        uint256[] memory words = new uint256[](1);
        words[0] = 7;
        coordinator.fulfill(1, words);
        assertEq(uint8(raffle.getRaffle(raffleId).phase), uint8(IRaffle.RafflePhase.Finalized));
    }

    function test_CancelRaffle_OnlyCreatorOrOwner() public {
        uint256 raffleId = _create();
        vm.prank(attacker);
        vm.expectRevert(IRaffle.NotCreator.selector);
        raffle.cancelRaffle(raffleId);
    }

    function test_CancelRaffle_RevertsOnceTicketsSold() public {
        uint256 raffleId = _create();
        vm.deal(buyer, 0.1 ether);
        vm.prank(buyer);
        raffle.buyTickets{ value: 0.1 ether }(raffleId, 1);
        vm.prank(seller);
        vm.expectRevert(IRaffle.TicketsAlreadySold.selector);
        raffle.cancelRaffle(raffleId);
    }

    function test_RetryRandomWinnerRequest_OnlyOwner() public {
        uint256 raffleId = _create();
        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        raffle.buyTickets{ value: 1 ether }(raffleId, 10);
        vm.prank(attacker);
        vm.expectRevert();
        raffle.retryRandomWinnerRequest(raffleId);
    }

    function test_Invariant_BalanceCoversActiveRaffleFunds_AfterPurchase() public {
        uint256 raffleId = _create();
        vm.deal(buyer, 0.3 ether);
        vm.prank(buyer);
        raffle.buyTickets{ value: 0.3 ether }(raffleId, 3);
        assertGe(address(raffle).balance, raffle.totalActiveRaffleFunds());
    }

    function test_BuyTickets_RevertsWhenEntrantRangeExceedsUint128() public {
        uint256 raffleId;
        vm.prank(seller);
        raffleId = raffle.createRaffle(address(nft), tokenId, 1, 0, 0, 0, 1 days);
        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        vm.expectRevert(IRaffle.InvalidQuantity.selector);
        raffle.buyTickets{ value: 0 }(raffleId, uint256(type(uint128).max) + 1);
    }

    function _createSecond() internal returns (uint256 raffleId) {
        uint256 tokenId2 = _mint(nft, seller2);
        vm.prank(seller2);
        nft.approve(address(raffle), tokenId2);
        vm.prank(seller2);
        raffleId = raffle.createRaffle(address(nft), tokenId2, 0.1 ether, 10, 0, 0, 1 days);
    }

    function test_CallbackCanCompleteWhilePaused() public {
        uint256 raffleId = _create();
        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        raffle.buyTickets{ value: 1 ether }(raffleId, 10);
        vm.prank(admin);
        raffle.pause();
        uint256[] memory words = new uint256[](1);
        words[0] = 123;
        coordinator.fulfill(1, words);
        assertEq(uint8(raffle.getRaffle(raffleId).phase), uint8(IRaffle.RafflePhase.Finalized));
    }

    function test_BuyTickets_RevertsWhilePaused() public {
        uint256 raffleId = _create();
        vm.prank(admin);
        raffle.pause();
        vm.deal(buyer, 0.1 ether);
        vm.prank(buyer);
        vm.expectRevert();
        raffle.buyTickets{ value: 0.1 ether }(raffleId, 1);
    }

    function test_RandomWinnerSelection_OnlyEverPicksAnActualTicketBuyer() public {
        uint256 raffleId = _create();
        vm.deal(buyer, 0.1 ether);
        vm.deal(buyer2, 0.9 ether);
        vm.prank(buyer);
        raffle.buyTickets{ value: 0.1 ether }(raffleId, 1);
        vm.prank(buyer2);
        raffle.buyTickets{ value: 0.9 ether }(raffleId, 9);
        uint256[] memory words = new uint256[](1);
        words[0] = 999999;
        coordinator.fulfill(1, words);
        address winner = raffle.getRaffle(raffleId).winner;
        assertTrue(winner == buyer || winner == buyer2);
        assertEq(nft.ownerOf(tokenId), winner);
    }

    function test_Constructor_RevertsOnEachInvalidInput() public {
        vm.expectRevert(IRaffle.ZeroAddress.selector);
        new Raffle(admin, address(0), FEE_BPS, address(coordinator), 1, bytes32(0), 200_000, 3, false);
        vm.expectRevert(IRaffle.ZeroAddress.selector);
        new Raffle(admin, address(treasury), FEE_BPS, address(0), 1, bytes32(0), 200_000, 3, false);
        vm.expectRevert(IRaffle.InvalidFeeBps.selector);
        new Raffle(admin, address(treasury), 1001, address(coordinator), 1, bytes32(0), 200_000, 3, false);
        vm.expectRevert(IRaffle.InvalidVRFConfig.selector);
        new Raffle(admin, address(treasury), FEE_BPS, address(coordinator), 1, bytes32(0), 200_000, 0, false);
    }

    function test_BuyTickets_RevertsBeforeScheduledStart() public {
        uint64 startAt = uint64(block.timestamp + 1 hours);
        vm.prank(seller);
        uint256 raffleId = raffle.createRaffle(address(nft), tokenId, 0.1 ether, 10, 0, startAt, 1 days);
        vm.deal(buyer, 0.1 ether);
        vm.prank(buyer);
        vm.expectRevert(IRaffle.InvalidPhase.selector);
        raffle.buyTickets{ value: 0.1 ether }(raffleId, 1);
    }

    function test_BuyTickets_RevertsAfterEndAt() public {
        uint256 raffleId = _create();
        vm.warp(block.timestamp + 1 days);
        vm.deal(buyer, 0.1 ether);
        vm.prank(buyer);
        vm.expectRevert(IRaffle.RaffleEnded.selector);
        raffle.buyTickets{ value: 0.1 ether }(raffleId, 1);
    }

    function test_BuyTickets_RevertsOnZeroQuantity() public {
        uint256 raffleId = _create();
        vm.prank(buyer);
        vm.expectRevert(IRaffle.InvalidQuantity.selector);
        raffle.buyTickets{ value: 0 }(raffleId, 0);
    }

    function test_BuyTickets_RevertsWhenSoldOut() public {
        uint256 raffleId;
        vm.prank(seller);
        raffleId = raffle.createRaffle(address(nft), tokenId, 0.1 ether, 2, 0, 0, 1 days);
        vm.deal(buyer, 0.3 ether);
        vm.prank(buyer);
        vm.expectRevert(IRaffle.SoldOut.selector);
        raffle.buyTickets{ value: 0.3 ether }(raffleId, 3);
    }

    function test_BuyTickets_RevertsAboveWalletLimit() public {
        uint256 raffleId;
        vm.prank(seller);
        raffleId = raffle.createRaffle(address(nft), tokenId, 0.1 ether, 10, 2, 0, 1 days);
        vm.deal(buyer, 0.3 ether);
        vm.prank(buyer);
        vm.expectRevert(IRaffle.TicketLimitExceeded.selector);
        raffle.buyTickets{ value: 0.3 ether }(raffleId, 3);
    }

    function test_BuyTickets_RevertsOnIncorrectPayment() public {
        uint256 raffleId = _create();
        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        vm.expectRevert(IRaffle.IncorrectPayment.selector);
        raffle.buyTickets{ value: 0.05 ether }(raffleId, 1);
    }

    function test_RawFulfillRandomWords_RevertsOnEmptyWordsAndUnknownRequest() public {
        uint256 raffleId = _create();
        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        raffle.buyTickets{ value: 1 ether }(raffleId, 10);
        uint256[] memory empty = new uint256[](0);
        vm.prank(address(coordinator));
        vm.expectRevert(IRaffle.InvalidRandomnessResponse.selector);
        raffle.rawFulfillRandomWords(1, empty);

        uint256[] memory words = new uint256[](1);
        words[0] = 1;
        vm.prank(address(coordinator));
        vm.expectRevert(IRaffle.UnknownRequestId.selector);
        raffle.rawFulfillRandomWords(999, words);
    }

    function test_RetryRandomWinnerRequest_RevertsWhenNotAwaitingRandomness() public {
        uint256 raffleId = _create();
        vm.prank(admin);
        vm.expectRevert(IRaffle.InvalidPhase.selector);
        raffle.retryRandomWinnerRequest(raffleId);
    }

    function test_FinalizeFailedRaffle_RevertsBeforeEndAtAndWhenTicketsSold() public {
        uint256 raffleId = _create();
        vm.expectRevert(IRaffle.RaffleNotYetEnded.selector);
        raffle.finalizeFailedRaffle(raffleId);

        vm.deal(buyer, 0.1 ether);
        vm.prank(buyer);
        raffle.buyTickets{ value: 0.1 ether }(raffleId, 1);
        vm.warp(block.timestamp + 1 days);
        vm.expectRevert(IRaffle.InvalidPhase.selector);
        raffle.finalizeFailedRaffle(raffleId);
    }

    function test_BuyTickets_RevertsForNonexistentRaffle() public {
        vm.prank(buyer);
        vm.expectRevert(IRaffle.RaffleNotFound.selector);
        raffle.buyTickets{ value: 0 }(999, 1);
    }

    function test_VRFConfig_RejectsNonContractCoordinator() public {
        vm.expectRevert(IRaffle.InvalidVRFCoordinator.selector);
        new Raffle(admin, address(treasury), FEE_BPS, address(1), 1, bytes32(uint256(1)), 200_000, 3, false);
    }

    function test_VRFConfig_RejectsInvalidParameters() public {
        vm.expectRevert(IRaffle.InvalidVRFConfig.selector);
        new Raffle(admin, address(treasury), FEE_BPS, address(coordinator), 0, bytes32(uint256(1)), 200_000, 3, false);
        vm.expectRevert(IRaffle.InvalidVRFConfig.selector);
        new Raffle(admin, address(treasury), FEE_BPS, address(coordinator), 1, bytes32(0), 200_000, 3, false);
        vm.expectRevert(IRaffle.InvalidVRFConfig.selector);
        new Raffle(admin, address(treasury), FEE_BPS, address(coordinator), 1, bytes32(uint256(1)), 200_000, 2, false);
    }

    function test_SetVRFConfigUpdatesAllFieldsAtomically() public {
        MockVRFCoordinatorV2Plus next = new MockVRFCoordinatorV2Plus();
        bytes32 nextKeyHash = keccak256("NEXT_KEY_HASH");
        vm.prank(admin);
        raffle.setVRFConfig(address(next), 99, nextKeyHash, 250_000, 10, true);
        assertEq(raffle.vrfCoordinator(), address(next));
        assertEq(raffle.subscriptionId(), 99);
        assertEq(raffle.keyHash(), nextKeyHash);
        assertEq(raffle.callbackGasLimit(), 250_000);
        assertEq(raffle.requestConfirmations(), 10);
        assertTrue(raffle.nativePayment());
    }

    function test_CancelStuckRaffleRequiresDelay() public {
        uint256 raffleId = _create();
        vm.deal(buyer, 0.1 ether);
        vm.prank(buyer);
        raffle.buyTickets{ value: 0.1 ether }(raffleId, 1);
        vm.warp(block.timestamp + 1 days);
        raffle.requestRandomWinner(raffleId);
        vm.prank(seller);
        vm.expectRevert(IRaffle.RandomnessNotYetDue.selector);
        raffle.cancelStuckRaffle(raffleId);
    }

    function test_RetryInvalidatesTheOldVrfRequest() public {
        uint256 id = _create();
        vm.deal(buyer, 0.1 ether);
        vm.prank(buyer);
        raffle.buyTickets{ value: 0.1 ether }(id, 1);
        vm.warp(block.timestamp + 1 days);
        raffle.requestRandomWinner(id);
        vm.warp(block.timestamp + raffle.RANDOMNESS_RETRY_DELAY());
        vm.prank(admin);
        raffle.retryRandomWinnerRequest(id);
        assertEq(raffle.getRaffle(id).vrfRequestId, 2);
        vm.expectRevert(IRaffle.UnknownRequestId.selector);
        coordinator.fulfillSingle(1, 5);
        coordinator.fulfillSingle(2, 5);
        assertEq(uint8(raffle.getRaffle(id).phase), uint8(IRaffle.RafflePhase.Finalized));
        assertEq(nft.ownerOf(tokenId), buyer);
    }

    function test_CancelStuckRaffleGuardsAndLateFulfillmentIsRejected() public {
        uint256 id = _create();
        uint256 otherId = _createSecond();
        vm.deal(buyer, 0.1 ether);
        vm.prank(buyer);
        raffle.buyTickets{ value: 0.1 ether }(id, 1);
        vm.warp(block.timestamp + 1 days);
        raffle.requestRandomWinner(id);

        vm.prank(attacker);
        vm.expectRevert(IRaffle.NotCreator.selector);
        raffle.cancelStuckRaffle(id);
        vm.prank(seller2);
        vm.expectRevert(IRaffle.NotCreator.selector);
        raffle.cancelStuckRaffle(id);
        vm.prank(seller2);
        vm.expectRevert(IRaffle.InvalidPhase.selector);
        raffle.cancelStuckRaffle(otherId);
        vm.prank(seller);
        vm.expectRevert(IRaffle.RandomnessNotYetDue.selector);
        raffle.cancelStuckRaffle(id);

        vm.warp(block.timestamp + raffle.STUCK_RAFFLE_CANCEL_DELAY());
        vm.prank(admin);
        raffle.cancelStuckRaffle(id);
        assertEq(uint8(raffle.getRaffle(id).phase), uint8(IRaffle.RafflePhase.Cancelled));
        assertEq(nft.ownerOf(tokenId), seller);
        vm.expectRevert(IRaffle.UnknownRequestId.selector);
        coordinator.fulfillSingle(1, 5);
    }

    function test_OnlyOwnerCanPauseAndConfigure() public {
        vm.startPrank(attacker);
        vm.expectRevert();
        raffle.pause();
        vm.expectRevert();
        raffle.unpause();
        vm.expectRevert();
        raffle.setFeeBps(100);
        vm.expectRevert();
        raffle.setVRFConfig(address(coordinator), 1, bytes32(uint256(1)), 200_000, 3, false);
        vm.stopPrank();
    }

    function test_PauseBlocksNewActivityButOwnerCanStillRetryRandomness() public {
        uint256 id = _create();
        vm.deal(buyer, 0.1 ether);
        vm.prank(buyer);
        raffle.buyTickets{ value: 0.1 ether }(id, 1);
        vm.warp(block.timestamp + 1 days);
        raffle.requestRandomWinner(id);
        vm.warp(block.timestamp + raffle.RANDOMNESS_RETRY_DELAY());
        vm.prank(admin);
        raffle.pause();
        vm.prank(seller);
        vm.expectRevert();
        raffle.createRaffle(address(nft), tokenId, 0.1 ether, 10, 0, 0, 1 days);
        vm.expectRevert();
        raffle.requestRandomWinner(id);
        vm.prank(admin);
        raffle.retryRandomWinnerRequest(id);
        assertEq(raffle.getRaffle(id).vrfRequestId, 2);
    }

    function test_RefundPipelineGuards() public {
        uint256 id = _create();
        vm.expectRevert(IRaffle.InvalidPhase.selector);
        raffle.processRaffleRefunds(id, 10);
        vm.prank(seller);
        raffle.cancelRaffle(id);
        vm.expectRevert(IRaffle.InvalidQuantity.selector);
        raffle.processRaffleRefunds(id, 0);
        uint256 oversizedBatch = raffle.MAX_REFUND_BATCH() + 1;
        vm.expectRevert(IRaffle.InvalidQuantity.selector);
        raffle.processRaffleRefunds(id, oversizedBatch);
        vm.expectRevert(IRaffle.InvalidQuantity.selector);
        raffle.processRaffleRefunds(id, 1);
        assertEq(raffle.refundCursor(id), 0);
        vm.prank(buyer);
        vm.expectRevert(IRaffle.RaffleRefundUnavailable.selector);
        raffle.claimRaffleRefund();
    }

    function test_RefundClaimFailureKeepsTheRefundClaimable() public {
        uint256 id = _create();
        RejectingRaffleBuyer rejecting = new RejectingRaffleBuyer();
        rejecting.buy{ value: 0.1 ether }(raffle, id, 1);
        vm.warp(block.timestamp + 1 days);
        raffle.requestRandomWinner(id);
        vm.warp(block.timestamp + raffle.STUCK_RAFFLE_CANCEL_DELAY());
        vm.prank(seller);
        raffle.cancelStuckRaffle(id);
        raffle.processRaffleRefunds(id, 10);
        vm.expectRevert(IRaffle.TransferFailed.selector);
        rejecting.claim(raffle);
        assertEq(raffle.raffleRefunds(address(rejecting)), 0.1 ether);
        assertEq(raffle.totalRaffleRefundLiability(), 0.1 ether);
        assertEq(address(raffle).balance, 0.1 ether);
    }
}

contract RejectingRaffleBuyer {
    function buy(Raffle raffle, uint256 id, uint256 quantity) external payable {
        raffle.buyTickets{ value: msg.value }(id, quantity);
    }

    function claim(Raffle raffle) external {
        raffle.claimRaffleRefund();
    }

    receive() external payable {
        revert();
    }
}

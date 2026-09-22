pragma solidity ^0.8.24;
import "../helpers/TestBase.sol";
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
        raffle.buyTickets{value: 0.1 ether}(raffleId, 1);
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
        vm.expectRevert(IRaffle.InvalidTime.selector);
        raffle.setVRFConfig(address(coordinator), 1, bytes32(0), 200_000, 0, false);
        vm.prank(admin);
        raffle.setFeeBps(0);
        assertEq(raffle.feeBps(), 0);
    }
    function test_rawFulfillRandomWords_RevertsForNonCoordinatorCaller() public {
        uint256 raffleId = _create();
        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        raffle.buyTickets{value: 1 ether}(raffleId, 10); 
        uint256[] memory words = new uint256[](1);
        words[0] = 42;
        vm.prank(attacker);
        vm.expectRevert(IRaffle.OnlyCoordinatorCanFulfill.selector);
        raffle.rawFulfillRandomWords(1, words);
    }
    function test_FINDING_CallbackValidatesAgainstCoordinatorAtRequestTime_NotLiveConfig() public {
        uint256 raffleId = _create();
        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        raffle.buyTickets{value: 1 ether}(raffleId, 10); 
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
        raffle.buyTickets{value: 0.1 ether}(raffleId, 1);
        vm.prank(seller);
        vm.expectRevert(IRaffle.TicketsAlreadySold.selector);
        raffle.cancelRaffle(raffleId);
    }
    function test_RetryRandomWinnerRequest_OnlyOwner() public {
        uint256 raffleId = _create();
        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        raffle.buyTickets{value: 1 ether}(raffleId, 10);
        vm.prank(attacker);
        vm.expectRevert(); 
        raffle.retryRandomWinnerRequest(raffleId);
    }
    function test_Invariant_BalanceCoversActiveRaffleFunds_AfterPurchase() public {
        uint256 raffleId = _create();
        vm.deal(buyer, 0.3 ether);
        vm.prank(buyer);
        raffle.buyTickets{value: 0.3 ether}(raffleId, 3);
        assertGe(address(raffle).balance, raffle.totalActiveRaffleFunds());
    }
    function test_BuyTickets_RevertsWhenEntrantRangeExceedsUint128() public {
        uint256 raffleId;
        vm.prank(seller);
        raffleId = raffle.createRaffle(address(nft), tokenId, 1, 0, 0, 0, 1 days);
        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        vm.expectRevert(IRaffle.InvalidQuantity.selector);
        raffle.buyTickets{value: 0}(raffleId, uint256(type(uint128).max) + 1);
    }
    function test_regression_ForcedEthDoesNotBrickTheContract() public {
        uint256 raffleId = _create();
        vm.deal(buyer, 0.1 ether);
        vm.prank(buyer);
        raffle.buyTickets{value: 0.1 ether}(raffleId, 1);
        ForceSender sender = new ForceSender{value: 1 wei}();
        sender.destroy(payable(address(raffle)));
        uint256 raffleId2 = _createSecond();
        vm.deal(buyer2, 0.9 ether);
        vm.prank(buyer2);
        raffle.buyTickets{value: 0.1 ether}(raffleId2, 1);
    }
    function _createSecond() internal returns (uint256 raffleId) {
        uint256 tokenId2 = _mint(nft, seller2);
        vm.prank(seller2);
        nft.approve(address(raffle), tokenId2);
        vm.prank(seller2);
        raffleId = raffle.createRaffle(address(nft), tokenId2, 0.1 ether, 10, 0, 0, 1 days);
    }
    function test_FINDING_CallbackSucceedsEvenWhilePaused() public {
        uint256 raffleId = _create();
        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        raffle.buyTickets{value: 1 ether}(raffleId, 10); 
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
        raffle.buyTickets{value: 0.1 ether}(raffleId, 1);
    }
    function test_RandomWinnerSelection_OnlyEverPicksAnActualTicketBuyer() public {
        uint256 raffleId = _create();
        vm.deal(buyer, 0.1 ether);
        vm.deal(buyer2, 0.9 ether);
        vm.prank(buyer);
        raffle.buyTickets{value: 0.1 ether}(raffleId, 1);
        vm.prank(buyer2);
        raffle.buyTickets{value: 0.9 ether}(raffleId, 9); 
        uint256[] memory words = new uint256[](1);
        words[0] = 999999; 
        coordinator.fulfill(1, words);
        address winner = raffle.getRaffle(raffleId).winner;
        assertTrue(winner == buyer || winner == buyer2);
        assertEq(nft.ownerOf(tokenId), winner);
    }
}
contract ForceSender {
    constructor() payable {}
    function destroy(address payable target) external {
        selfdestruct(target);
    }
}

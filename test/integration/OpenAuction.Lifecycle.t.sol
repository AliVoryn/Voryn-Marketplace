pragma solidity ^0.8.24;
import "../helpers/TestBase.sol";
contract OpenAuctionLifecycleTest is ProtocolTestBase {
    OpenAuction internal auctionHouse;
    uint256 internal tokenId;
    function setUp() public {
        _setUpCore();
        auctionHouse = _deployOpenAuction(address(treasury));
        vm.prank(admin);
        treasury.setAuthorizedPayer(address(auctionHouse), true);
        tokenId = _mint(nft, seller);
        vm.prank(seller);
        nft.approve(address(auctionHouse), tokenId);
    }
    function _createBasicAuction() internal returns (uint256 auctionId) {
        vm.prank(seller);
        auctionId = auctionHouse.createAuction(address(nft), tokenId, 1 ether, 0.1 ether, 0, 1 days);
    }
    function test_CreateAuction_EscrowsNFT() public {
        uint256 auctionId = _createBasicAuction();
        assertEq(nft.ownerOf(tokenId), address(auctionHouse));
        IAuction.Auction memory a = auctionHouse.getAuction(auctionId);
        assertEq(uint8(a.phase), uint8(IAuction.Phase.Created));
    }
    function test_CreateAuction_RevertsIfCallerIsNotOwner() public {
        vm.prank(attacker);
        vm.expectRevert(IAuction.NotSeller.selector);
        auctionHouse.createAuction(address(nft), tokenId, 1 ether, 0.1 ether, 0, 1 days);
    }
    function test_PlaceBid_BelowReserveReverts() public {
        uint256 auctionId = _createBasicAuction();
        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        vm.expectRevert(IAuction.BidTooLow.selector);
        auctionHouse.placeBid{value: 0.5 ether}(auctionId);
    }
    function test_PlaceBid_OutbidRefundsPreviousBidder() public {
        uint256 auctionId = _createBasicAuction();
        vm.deal(buyer, 2 ether);
        vm.deal(buyer2, 2 ether);
        vm.prank(buyer);
        auctionHouse.placeBid{value: 1 ether}(auctionId);
        vm.prank(buyer2);
        auctionHouse.placeBid{value: 1.1 ether}(auctionId); 
        assertEq(auctionHouse.getRefund(buyer), 1 ether);
        assertEq(auctionHouse.getAuction(auctionId).highestBidder, buyer2);
        _assertEscrowSolvent();
    }
    function test_PlaceBid_BelowMinIncrementReverts() public {
        uint256 auctionId = _createBasicAuction();
        vm.deal(buyer, 2 ether);
        vm.prank(buyer);
        auctionHouse.placeBid{value: 1 ether}(auctionId);
        vm.deal(buyer2, 2 ether);
        vm.prank(buyer2);
        vm.expectRevert(IAuction.BidTooLow.selector); 
        auctionHouse.placeBid{value: 1.05 ether}(auctionId);
    }
    function test_AntiSnipe_ExtendsWithinWindow() public {
        uint256 auctionId = _createBasicAuction();
        IAuction.Auction memory a0 = auctionHouse.getAuction(auctionId);
        vm.warp(a0.endAt - 1 minutes); 
        vm.deal(buyer, 2 ether);
        vm.prank(buyer);
        auctionHouse.placeBid{value: 1 ether}(auctionId);
        IAuction.Auction memory a1 = auctionHouse.getAuction(auctionId);
        assertGt(a1.endAt, a0.endAt, "bid inside the anti-snipe window must push endAt back");
        assertEq(a1.extensionsUsed, 1);
    }
    function test_AntiSnipe_RespectsMaxExtensions() public {
        uint256 auctionId = _createBasicAuction();
        vm.deal(buyer, 10 ether);
        vm.deal(buyer2, 10 ether);
        for (uint256 i = 0; i < 3; i++) {
            IAuction.Auction memory a = auctionHouse.getAuction(auctionId);
            vm.warp(a.endAt - 1 minutes);
            address bidder = i % 2 == 0 ? buyer : buyer2;
            vm.prank(bidder);
            auctionHouse.placeBid{value: (1 ether) + (i + 1) * 0.2 ether}(auctionId);
        }
        IAuction.Auction memory beforeFourth = auctionHouse.getAuction(auctionId);
        assertEq(beforeFourth.extensionsUsed, 3, "maxExtensions is 3 by construction");
        vm.warp(beforeFourth.endAt - 1 minutes);
        vm.prank(buyer);
        auctionHouse.placeBid{value: 3 ether}(auctionId);
        IAuction.Auction memory afterFourth = auctionHouse.getAuction(auctionId);
        assertEq(afterFourth.extensionsUsed, 3, "a 4th extension must never be granted");
    }
    function test_Finalize_SuccessfulAuction_PaysTreasuryAndTransfersNFT() public {
        uint256 auctionId = _createBasicAuction();
        vm.deal(buyer, 2 ether);
        vm.prank(buyer);
        auctionHouse.placeBid{value: 1 ether}(auctionId);
        IAuction.Auction memory a = auctionHouse.getAuction(auctionId);
        vm.warp(a.endAt);
        auctionHouse.finalizeAuction(auctionId);
        assertEq(nft.ownerOf(tokenId), buyer);
        assertEq(treasury.claimable(seller), 0.975 ether); 
        _assertEscrowSolvent();
    }
    function test_Finalize_NoBids_ReturnsNFTAndMarksFailed() public {
        uint256 auctionId = _createBasicAuction();
        IAuction.Auction memory a = auctionHouse.getAuction(auctionId);
        vm.warp(a.endAt);
        auctionHouse.finalizeAuction(auctionId);
        IAuction.Auction memory after_ = auctionHouse.getAuction(auctionId);
        assertEq(uint8(after_.phase), uint8(IAuction.Phase.Failed));
        assertEq(nft.ownerOf(tokenId), seller);
    }
    function test_Finalize_RevertsBeforeEndAt() public {
        uint256 auctionId = _createBasicAuction();
        vm.expectRevert(IAuction.NotFinalizable.selector);
        auctionHouse.finalizeAuction(auctionId);
    }
    function test_Finalize_CannotBeCalledTwice() public {
        uint256 auctionId = _createBasicAuction();
        IAuction.Auction memory a = auctionHouse.getAuction(auctionId);
        vm.warp(a.endAt);
        auctionHouse.finalizeAuction(auctionId);
        vm.expectRevert(IAuction.NotFinalizable.selector);
        auctionHouse.finalizeAuction(auctionId);
    }
    function test_Cancel_BeforeAnyBid_ReturnsNFT() public {
        uint256 auctionId = _createBasicAuction();
        vm.prank(seller);
        auctionHouse.cancelAuction(auctionId);
        assertEq(nft.ownerOf(tokenId), seller);
    }
    function test_Cancel_WithActiveBid_RefundsBidder() public {
        uint256 auctionId = _createBasicAuction();
        vm.deal(buyer, 2 ether);
        vm.prank(buyer);
        auctionHouse.placeBid{value: 1 ether}(auctionId);
        vm.prank(seller);
        auctionHouse.cancelAuction(auctionId);
        assertEq(auctionHouse.getRefund(buyer), 1 ether);
        _assertEscrowSolvent();
    }
    function test_Cancel_RevertsForNonSellerNonOwner() public {
        uint256 auctionId = _createBasicAuction();
        vm.prank(attacker);
        vm.expectRevert(IAuction.NotSeller.selector);
        auctionHouse.cancelAuction(auctionId);
    }
    function test_Buyout_SettlesImmediatelyAndSkipsRemainingTime() public {
        uint256 auctionId = _createBasicAuction();
        vm.prank(seller);
        auctionHouse.configureBuyout(auctionId, 5 ether);
        vm.deal(buyer, 5 ether);
        vm.prank(buyer);
        auctionHouse.buyout{value: 5 ether}(auctionId);
        assertEq(nft.ownerOf(tokenId), buyer);
        assertEq(uint8(auctionHouse.getAuction(auctionId).phase), uint8(IAuction.Phase.Finalized));
        _assertEscrowSolvent();
    }
    function test_WithdrawRefund_PaysAndZeroesOut() public {
        uint256 auctionId = _createBasicAuction();
        vm.deal(buyer, 2 ether);
        vm.deal(buyer2, 2 ether);
        vm.prank(buyer);
        auctionHouse.placeBid{value: 1 ether}(auctionId);
        vm.prank(buyer2);
        auctionHouse.placeBid{value: 1.1 ether}(auctionId);
        uint256 before = buyer.balance;
        vm.prank(buyer);
        auctionHouse.withdrawRefund();
        assertEq(buyer.balance, before + 1 ether);
        _assertEscrowSolvent();
    }
    function _assertEscrowSolvent() internal view {
        assertGe(
            address(auctionHouse).balance,
            auctionHouse.totalActiveBidLiability() + auctionHouse.totalRefundLiability()
        );
    }
}

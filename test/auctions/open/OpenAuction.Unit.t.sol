// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import "../../support/TestBase.sol";

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
        auctionHouse.placeBid{ value: 0.5 ether }(auctionId);
    }

    function test_PlaceBid_OutbidRefundsPreviousBidder() public {
        uint256 auctionId = _createBasicAuction();
        vm.deal(buyer, 2 ether);
        vm.deal(buyer2, 2 ether);
        vm.prank(buyer);
        auctionHouse.placeBid{ value: 1 ether }(auctionId);
        vm.prank(buyer2);
        auctionHouse.placeBid{ value: 1.1 ether }(auctionId);
        assertEq(auctionHouse.getRefund(buyer), 1 ether);
        assertEq(auctionHouse.getAuction(auctionId).highestBidder, buyer2);
        _assertEscrowSolvent();
    }

    function test_PlaceBid_BelowMinIncrementReverts() public {
        uint256 auctionId = _createBasicAuction();
        vm.deal(buyer, 2 ether);
        vm.prank(buyer);
        auctionHouse.placeBid{ value: 1 ether }(auctionId);
        vm.deal(buyer2, 2 ether);
        vm.prank(buyer2);
        vm.expectRevert(IAuction.BidTooLow.selector);
        auctionHouse.placeBid{ value: 1.05 ether }(auctionId);
    }

    function test_AntiSnipe_ExtendsWithinWindow() public {
        uint256 auctionId = _createBasicAuction();
        IAuction.Auction memory a0 = auctionHouse.getAuction(auctionId);
        vm.warp(a0.endAt - 1 minutes);
        vm.deal(buyer, 2 ether);
        vm.prank(buyer);
        auctionHouse.placeBid{ value: 1 ether }(auctionId);
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
            auctionHouse.placeBid{ value: (1 ether) + (i + 1) * 0.2 ether }(auctionId);
        }
        IAuction.Auction memory beforeFourth = auctionHouse.getAuction(auctionId);
        assertEq(beforeFourth.extensionsUsed, 3, "maxExtensions is 3 by construction");
        vm.warp(beforeFourth.endAt - 1 minutes);
        vm.prank(buyer);
        auctionHouse.placeBid{ value: 3 ether }(auctionId);
        IAuction.Auction memory afterFourth = auctionHouse.getAuction(auctionId);
        assertEq(afterFourth.extensionsUsed, 3, "a 4th extension must never be granted");
    }

    function test_Finalize_SuccessfulAuction_PaysTreasuryAndTransfersNFT() public {
        uint256 auctionId = _createBasicAuction();
        vm.deal(buyer, 2 ether);
        vm.prank(buyer);
        auctionHouse.placeBid{ value: 1 ether }(auctionId);
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
        auctionHouse.placeBid{ value: 1 ether }(auctionId);
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
        auctionHouse.buyout{ value: 5 ether }(auctionId);
        assertEq(nft.ownerOf(tokenId), buyer);
        assertEq(uint8(auctionHouse.getAuction(auctionId).phase), uint8(IAuction.Phase.Finalized));
        _assertEscrowSolvent();
    }

    function test_WithdrawRefund_PaysAndZeroesOut() public {
        uint256 auctionId = _createBasicAuction();
        vm.deal(buyer, 2 ether);
        vm.deal(buyer2, 2 ether);
        vm.prank(buyer);
        auctionHouse.placeBid{ value: 1 ether }(auctionId);
        vm.prank(buyer2);
        auctionHouse.placeBid{ value: 1.1 ether }(auctionId);
        uint256 before = buyer.balance;
        vm.prank(buyer);
        auctionHouse.withdrawRefund();
        assertEq(buyer.balance, before + 1 ether);
        _assertEscrowSolvent();
    }

    function _assertEscrowSolvent() internal view {
        assertGe(
            address(auctionHouse).balance, auctionHouse.totalActiveBidLiability() + auctionHouse.totalRefundLiability()
        );
    }

    function test_Constructor_RevertsForZeroTreasuryAndTooHighFee() public {
        vm.expectRevert(IAuction.InvalidTreasury.selector);
        new OpenAuction(admin, address(0), FEE_BPS);
        vm.expectRevert(IAuction.InvalidFeeBps.selector);
        new OpenAuction(admin, address(treasury), 1001);
    }

    function test_CreateAuction_RevertsOnEachInvalidInput() public {
        vm.startPrank(seller);
        vm.expectRevert(IAuction.ZeroAddress.selector);
        auctionHouse.createAuction(address(0), tokenId, 1 ether, 0.1 ether, 0, 1 days);
        vm.expectRevert(IAuction.InvalidPrice.selector);
        auctionHouse.createAuction(address(nft), tokenId, 0, 0.1 ether, 0, 1 days);
        vm.expectRevert(IAuction.InvalidIncrement.selector);
        auctionHouse.createAuction(address(nft), tokenId, 1 ether, 0, 0, 1 days);
        vm.expectRevert(IAuction.InvalidTime.selector);
        auctionHouse.createAuction(address(nft), tokenId, 1 ether, 0.1 ether, 0, 0);
        vm.warp(block.timestamp + 1);
        vm.expectRevert(IAuction.InvalidTime.selector);
        auctionHouse.createAuction(address(nft), tokenId, 1 ether, 0.1 ether, uint64(block.timestamp - 1), 1 days);
        vm.stopPrank();
    }

    function test_CreateAuction_FutureStartIsScheduledAndStartAuctionActivates() public {
        uint64 startAt = uint64(block.timestamp + 1 hours);
        vm.prank(seller);
        uint256 auctionId = auctionHouse.createAuction(address(nft), tokenId, 1 ether, 0.1 ether, startAt, 1 days);
        assertEq(uint8(auctionHouse.getAuction(auctionId).phase), uint8(IAuction.Phase.Scheduled));

        vm.prank(attacker);
        vm.expectRevert(IAuction.NotSeller.selector);
        auctionHouse.startAuction(auctionId);

        vm.prank(seller);
        vm.expectRevert(IAuction.InvalidTime.selector);
        auctionHouse.startAuction(auctionId);

        vm.warp(startAt);
        vm.prank(seller);
        auctionHouse.startAuction(auctionId);
        assertEq(uint8(auctionHouse.getAuction(auctionId).phase), uint8(IAuction.Phase.Active));

        vm.prank(seller);
        vm.expectRevert(IAuction.InvalidPhase.selector);
        auctionHouse.startAuction(auctionId);
    }

    function test_StartAuction_RevertsAfterEndAt() public {
        uint64 startAt = uint64(block.timestamp + 1 hours);
        vm.prank(seller);
        uint256 auctionId = auctionHouse.createAuction(address(nft), tokenId, 1 ether, 0.1 ether, startAt, 1 days);
        IAuction.Auction memory a = auctionHouse.getAuction(auctionId);
        vm.warp(a.endAt);
        vm.prank(seller);
        vm.expectRevert(IAuction.InvalidPhase.selector);
        auctionHouse.startAuction(auctionId);
    }

    function test_ConfigureBuyout_RevertsForUnauthorizedAndInvalidPrice() public {
        uint256 auctionId = _createBasicAuction();
        vm.prank(attacker);
        vm.expectRevert(IAuction.NotSeller.selector);
        auctionHouse.configureBuyout(auctionId, 5 ether);

        vm.prank(seller);
        vm.expectRevert(IAuction.InvalidBuyout.selector);
        auctionHouse.configureBuyout(auctionId, 1 ether);

        IAuction.Auction memory a = auctionHouse.getAuction(auctionId);
        vm.warp(a.endAt);
        vm.prank(seller);
        vm.expectRevert(IAuction.InvalidPhase.selector);
        auctionHouse.configureBuyout(auctionId, 5 ether);
    }

    function test_PlaceBid_RevertsWhenNotYetActive() public {
        uint64 startAt = uint64(block.timestamp + 1 hours);
        vm.prank(seller);
        uint256 auctionId = auctionHouse.createAuction(address(nft), tokenId, 1 ether, 0.1 ether, startAt, 1 days);
        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        vm.expectRevert(IAuction.InvalidPhase.selector);
        auctionHouse.placeBid{ value: 1 ether }(auctionId);
    }

    function test_PlaceBid_RevertsAfterEndAt() public {
        uint256 auctionId = _createBasicAuction();
        IAuction.Auction memory a = auctionHouse.getAuction(auctionId);
        vm.warp(a.endAt);
        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        vm.expectRevert(IAuction.InvalidPhase.selector);
        auctionHouse.placeBid{ value: 1 ether }(auctionId);
    }

    function test_Buyout_RevertsWhenNotEnabledAndWrongPrice() public {
        uint256 auctionId = _createBasicAuction();
        vm.deal(buyer, 5 ether);
        vm.prank(buyer);
        vm.expectRevert(IAuction.InvalidBuyout.selector);
        auctionHouse.buyout{ value: 5 ether }(auctionId);

        vm.prank(seller);
        auctionHouse.configureBuyout(auctionId, 5 ether);
        vm.prank(buyer);
        vm.expectRevert(IAuction.BidTooLow.selector);
        auctionHouse.buyout{ value: 4 ether }(auctionId);
    }

    function test_Buyout_RefundsExistingHighestBidder() public {
        uint256 auctionId = _createBasicAuction();
        vm.deal(buyer, 2 ether);
        vm.prank(buyer);
        auctionHouse.placeBid{ value: 1 ether }(auctionId);

        vm.prank(seller);
        auctionHouse.configureBuyout(auctionId, 5 ether);
        vm.deal(buyer2, 5 ether);
        vm.prank(buyer2);
        auctionHouse.buyout{ value: 5 ether }(auctionId);

        assertEq(auctionHouse.getRefund(buyer), 1 ether);
        assertEq(nft.ownerOf(tokenId), buyer2);
        _assertEscrowSolvent();
    }

    function test_Buyout_RevertsAfterEndAt() public {
        uint256 auctionId = _createBasicAuction();
        vm.prank(seller);
        auctionHouse.configureBuyout(auctionId, 5 ether);
        IAuction.Auction memory a = auctionHouse.getAuction(auctionId);
        vm.warp(a.endAt);
        vm.deal(buyer, 5 ether);
        vm.prank(buyer);
        vm.expectRevert(IAuction.InvalidPhase.selector);
        auctionHouse.buyout{ value: 5 ether }(auctionId);
    }

    function test_EndAuction_TransitionsToEndedAndRejectsEarlyOrWrongPhase() public {
        uint256 auctionId = _createBasicAuction();
        vm.expectRevert(IAuction.NotFinalizable.selector);
        auctionHouse.endAuction(auctionId);

        IAuction.Auction memory a = auctionHouse.getAuction(auctionId);
        vm.warp(a.endAt);
        auctionHouse.endAuction(auctionId);
        assertEq(uint8(auctionHouse.getAuction(auctionId).phase), uint8(IAuction.Phase.Ended));

        vm.expectRevert(IAuction.InvalidPhase.selector);
        auctionHouse.endAuction(auctionId);
    }

    function test_Cancel_RevertsWhenAlreadyFinalized() public {
        uint256 auctionId = _createBasicAuction();
        vm.deal(buyer, 2 ether);
        vm.prank(buyer);
        auctionHouse.placeBid{ value: 1 ether }(auctionId);
        IAuction.Auction memory a = auctionHouse.getAuction(auctionId);
        vm.warp(a.endAt);
        auctionHouse.finalizeAuction(auctionId);

        vm.prank(seller);
        vm.expectRevert(IAuction.InvalidPhase.selector);
        auctionHouse.cancelAuction(auctionId);
    }

    function test_Cancel_OwnerCanCancelEvenWhenNotSeller() public {
        uint256 auctionId = _createBasicAuction();
        vm.prank(admin);
        auctionHouse.cancelAuction(auctionId);
        assertEq(nft.ownerOf(tokenId), seller);
    }

    function test_WithdrawRefund_RevertsWhenNothingToWithdraw() public {
        vm.prank(buyer);
        vm.expectRevert(IAuction.SettlementFailed.selector);
        auctionHouse.withdrawRefund();
    }

    function test_Pause_BlocksCreateAndBid() public {
        uint256 auctionId = _createBasicAuction();
        vm.prank(admin);
        auctionHouse.pause();

        vm.prank(seller);
        vm.expectRevert();
        auctionHouse.createAuction(address(nft), tokenId, 1 ether, 0.1 ether, 0, 1 days);

        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        vm.expectRevert();
        auctionHouse.placeBid{ value: 1 ether }(auctionId);

        vm.prank(admin);
        auctionHouse.unpause();
        vm.prank(buyer);
        auctionHouse.placeBid{ value: 1 ether }(auctionId);
    }

    function test_DirectETH_Reverts() public {
        vm.deal(attacker, 1 ether);
        vm.prank(attacker);
        (bool ok,) = address(auctionHouse).call{ value: 1 ether }("");
        assertFalse(ok);
    }

    function test_BidHistoryAndEscrowViews() public {
        uint256 auctionId = _createBasicAuction();
        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        auctionHouse.placeBid{ value: 1 ether }(auctionId);
        vm.deal(buyer2, 1.1 ether);
        vm.prank(buyer2);
        auctionHouse.placeBid{ value: 1.1 ether }(auctionId);
        assertEq(auctionHouse.bidHistoryLength(auctionId), 2);
        OpenAuction.BidSnapshot memory first = auctionHouse.bidHistoryAt(auctionId, 0);
        OpenAuction.BidSnapshot memory second = auctionHouse.bidHistoryAt(auctionId, 1);
        assertEq(first.bidder, buyer);
        assertEq(first.amount, 1 ether);
        assertEq(second.bidder, buyer2);
        assertEq(second.amount, 1.1 ether);
        assertEq(auctionHouse.escrowedBalance(), 2.1 ether);
        assertEq(auctionHouse.getRefund(buyer), 1 ether);
        vm.expectRevert();
        auctionHouse.bidHistoryAt(auctionId, 2);
    }

    function test_ConfigureBuyout_CanBeUpdatedBySellerAndOwner() public {
        uint256 auctionId = _createBasicAuction();
        vm.prank(seller);
        auctionHouse.configureBuyout(auctionId, 5 ether);
        assertEq(auctionHouse.buyoutPrice(auctionId), 5 ether);
        vm.prank(admin);
        auctionHouse.configureBuyout(auctionId, 4 ether);
        assertTrue(auctionHouse.buyoutEnabled(auctionId));
        assertEq(auctionHouse.buyoutPrice(auctionId), 4 ether);
    }

    function test_PlaceBid_SameBidderOutbidsSelfAndCreditsPreviousBid() public {
        uint256 auctionId = _createBasicAuction();
        vm.deal(buyer, 2.2 ether);
        vm.startPrank(buyer);
        auctionHouse.placeBid{ value: 1 ether }(auctionId);
        auctionHouse.placeBid{ value: 1.2 ether }(auctionId);
        vm.stopPrank();
        assertEq(auctionHouse.getAuction(auctionId).highestBid, 1.2 ether);
        assertEq(auctionHouse.getRefund(buyer), 1 ether);
        assertEq(auctionHouse.totalRefundLiability(), 1 ether);
        assertEq(auctionHouse.totalActiveBidLiability(), 1.2 ether);
        _assertEscrowSolvent();
    }

    function test_Buyout_ByCurrentHighestBidderRefundsTheirOwnBid() public {
        uint256 auctionId = _createBasicAuction();
        vm.prank(seller);
        auctionHouse.configureBuyout(auctionId, 5 ether);
        vm.deal(buyer, 6 ether);
        vm.startPrank(buyer);
        auctionHouse.placeBid{ value: 1 ether }(auctionId);
        auctionHouse.buyout{ value: 5 ether }(auctionId);
        vm.stopPrank();
        assertEq(nft.ownerOf(tokenId), buyer);
        assertEq(auctionHouse.getRefund(buyer), 1 ether);
        assertEq(auctionHouse.totalActiveBidLiability(), 0);
        assertEq(treasury.claimable(seller), 4.875 ether);
        _assertEscrowSolvent();
    }

    function test_Pause_KeepsSellerExitAndRefundWithdrawalsOpen() public {
        uint256 auctionId = _createBasicAuction();
        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        auctionHouse.placeBid{ value: 1 ether }(auctionId);
        vm.deal(buyer2, 1.1 ether);
        vm.prank(buyer2);
        auctionHouse.placeBid{ value: 1.1 ether }(auctionId);
        vm.prank(admin);
        auctionHouse.pause();

        vm.deal(attacker, 2 ether);
        vm.prank(attacker);
        vm.expectRevert();
        auctionHouse.placeBid{ value: 2 ether }(auctionId);
        vm.expectRevert();
        auctionHouse.finalizeAuction(auctionId);

        vm.prank(buyer);
        auctionHouse.withdrawRefund();
        assertEq(buyer.balance, 1 ether);
        vm.prank(seller);
        auctionHouse.cancelAuction(auctionId);
        assertEq(nft.ownerOf(tokenId), seller);
        vm.prank(buyer2);
        auctionHouse.withdrawRefund();
        assertEq(buyer2.balance, 1.1 ether);
        assertEq(auctionHouse.escrowedBalance(), 0);
    }
}

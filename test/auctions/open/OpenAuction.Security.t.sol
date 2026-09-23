// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../../support/TestBase.sol";

contract OpenAuctionSecurityTest is ProtocolTestBase {
    OpenAuction internal auction;
    uint256 internal tokenId;
    uint256 internal auctionId;

    function setUp() public {
        _setUpCore();
        auction = _deployOpenAuction(address(treasury));
        tokenId = _mint(nft, seller);
        vm.prank(seller);
        nft.approve(address(auction), tokenId);
        vm.prank(seller);
        auctionId = auction.createAuction(address(nft), tokenId, 1 ether, 0.1 ether, 0, 1 days);
    }

    function test_UnauthorizedCannotPauseOrUnpause() public {
        vm.prank(attacker);
        vm.expectRevert();
        auction.pause();

        vm.prank(attacker);
        vm.expectRevert();
        auction.unpause();
    }

    function test_NonSellerCannotConfigureBuyout() public {
        vm.prank(attacker);
        vm.expectRevert(IAuction.NotSeller.selector);
        auction.configureBuyout(auctionId, 2 ether);
    }

    function test_SellerCannotBidOwnAuction() public {
        vm.deal(seller, 2 ether);
        vm.prank(seller);
        vm.expectRevert(IAuction.SellerCannotBid.selector);
        auction.placeBid{ value: 1 ether }(auctionId);
    }

    function test_SellerCannotBuyOwnAuction() public {
        vm.deal(seller, 3 ether);
        vm.prank(seller);
        auction.configureBuyout(auctionId, 2 ether);
        vm.prank(seller);
        vm.expectRevert(IAuction.NotSeller.selector);
        auction.buyout{ value: 2 ether }(auctionId);
    }
}

contract OpenAuctionAdditionalSecurityTest is ProtocolTestBase {
    OpenAuction internal auction;
    uint256 internal tokenId;

    function setUp() public {
        _setUpCore();
        auction = _deployOpenAuction(address(treasury));
        vm.prank(admin);
        treasury.setAuthorizedPayer(address(auction), true);
        tokenId = _mint(nft, seller);
        vm.prank(seller);
        nft.approve(address(auction), tokenId);
    }

    function test_OwnerCannotCancelAfterAuctionEnd() public {
        vm.prank(seller);
        uint256 id = auction.createAuction(address(nft), tokenId, 1 ether, 0.1 ether, 0, 1 days);
        vm.warp(block.timestamp + 1 days);
        vm.prank(admin);
        vm.expectRevert(IAuction.InvalidPhase.selector);
        auction.cancelAuction(id);
    }

    function test_BuyoutCannotExecuteBelowExistingBid() public {
        vm.prank(seller);
        uint256 id = auction.createAuction(address(nft), tokenId, 1 ether, 0.1 ether, 0, 1 days);
        vm.prank(seller);
        auction.configureBuyout(id, 3 ether);
        vm.deal(buyer, 3 ether);
        vm.prank(buyer);
        auction.placeBid{ value: 3 ether }(id);
        vm.deal(buyer2, 3 ether);
        vm.prank(buyer2);
        vm.expectRevert(IAuction.InvalidBuyout.selector);
        auction.buyout{ value: 3 ether }(id);
    }

    function test_RejectingBidderCannotBlockOutbiddingAndKeepsItsRefund() public {
        vm.prank(seller);
        uint256 id = auction.createAuction(address(nft), tokenId, 1 ether, 0.1 ether, 0, 1 days);
        RejectingOpenBidder rejecting = new RejectingOpenBidder();
        rejecting.bid{ value: 1 ether }(auction, id);
        vm.deal(buyer, 1.1 ether);
        vm.prank(buyer);
        auction.placeBid{ value: 1.1 ether }(id);
        assertEq(auction.getAuction(id).highestBidder, buyer);
        assertEq(auction.getRefund(address(rejecting)), 1 ether);
        vm.expectRevert(IAuction.SettlementFailed.selector);
        rejecting.pull(auction);
        assertEq(auction.getRefund(address(rejecting)), 1 ether);
        assertEq(auction.totalRefundLiability(), 1 ether);
        assertEq(auction.escrowedBalance(), 2.1 ether);
    }
}

contract RejectingOpenBidder {
    function bid(OpenAuction auction, uint256 id) external payable {
        auction.placeBid{ value: msg.value }(id);
    }

    function pull(OpenAuction auction) external {
        auction.withdrawRefund();
    }

    receive() external payable {
        revert();
    }
}

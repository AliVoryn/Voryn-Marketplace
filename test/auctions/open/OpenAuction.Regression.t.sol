// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../../support/TestBase.sol";

contract OpenAuctionRegressionTest is ProtocolTestBase {
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

    function _createAuction(uint64 duration) internal returns (uint256 id) {
        vm.prank(seller);
        id = auction.createAuction(address(nft), tokenId, 1 ether, 0.1 ether, 0, duration);
    }

    function test_Cancel_RevertsAfterBiddingEnded() public {
        uint256 auctionId = _createAuction(1 days);
        vm.warp(block.timestamp + 1 days);
        vm.prank(seller);
        vm.expectRevert(IAuction.InvalidPhase.selector);
        auction.cancelAuction(auctionId);
    }

    function test_CreateAuction_RevertsOnTimestampOverflow() public {
        uint64 startAt = type(uint64).max - 1;
        vm.prank(seller);
        vm.expectRevert(IAuction.InvalidTime.selector);
        auction.createAuction(address(nft), tokenId, 1 ether, 0.1 ether, startAt, 2);
    }

    function test_UnknownAuctionIdIsRejectedByEveryEntryPoint() public {
        uint256 unknownId = 42;
        vm.deal(buyer, 2 ether);

        vm.expectRevert(IAuction.AuctionNotFound.selector);
        auction.startAuction(unknownId);
        vm.expectRevert(IAuction.AuctionNotFound.selector);
        auction.endAuction(unknownId);
        vm.expectRevert(IAuction.AuctionNotFound.selector);
        auction.finalizeAuction(unknownId);
        vm.prank(buyer);
        vm.expectRevert(IAuction.AuctionNotFound.selector);
        auction.placeBid{ value: 1 ether }(unknownId);
        vm.prank(buyer);
        vm.expectRevert(IAuction.AuctionNotFound.selector);
        auction.buyout{ value: 1 ether }(unknownId);
        vm.prank(admin);
        vm.expectRevert(IAuction.AuctionNotFound.selector);
        auction.configureBuyout(unknownId, 2 ether);
        vm.prank(admin);
        vm.expectRevert(IAuction.AuctionNotFound.selector);
        auction.cancelAuction(unknownId);

        IAuction.Auction memory untouched = auction.getAuction(unknownId);
        assertEq(untouched.seller, address(0));
        assertEq(uint8(untouched.phase), uint8(IAuction.Phase.Created));
    }

    function test_EndAuction_OnUnknownIdCannotPreEmptAFutureAuction() public {
        vm.expectRevert(IAuction.AuctionNotFound.selector);
        auction.endAuction(1);
        uint256 id = _createAuction(1 days);
        assertEq(id, 1);
        assertEq(uint8(auction.getAuction(id).phase), uint8(IAuction.Phase.Created));
        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        auction.placeBid{ value: 1 ether }(id);
        assertEq(auction.getAuction(id).highestBidder, buyer);
    }

    function test_BidNearUint64MaxRevertsInsteadOfWrappingTheExtendedDeadline() public {
        uint64 duration = type(uint64).max - uint64(block.timestamp);
        uint256 id = _createAuction(duration);
        assertEq(auction.getAuction(id).endAt, type(uint64).max);
        vm.warp(uint256(type(uint64).max) - 60);
        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        vm.expectRevert(IAuction.InvalidTime.selector);
        auction.placeBid{ value: 1 ether }(id);
        assertEq(auction.getAuction(id).highestBid, 0);
    }
}

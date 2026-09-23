// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../../support/TestBase.sol";

contract OpenAuctionFuzzTest is ProtocolTestBase {
    OpenAuction internal auction;
    uint256 internal tokenId;

    function setUp() public {
        _setUpCore();
        auction = _deployOpenAuction(address(treasury));
        tokenId = _mint(nft, seller);
        vm.prank(seller);
        nft.approve(address(auction), tokenId);
    }

    function testFuzz_ConfigureBuyout_OnlyPricesAboveReserveEnableBuyout(uint96 rawPrice) public {
        uint256 price = bound(uint256(rawPrice), 1 ether + 1, 1000 ether);
        vm.prank(seller);
        uint256 auctionId = auction.createAuction(address(nft), tokenId, 1 ether, 0.1 ether, 0, 1 days);
        vm.prank(seller);
        auction.configureBuyout(auctionId, price);
        assertTrue(auction.buyoutEnabled(auctionId));
        assertEq(auction.buyoutPrice(auctionId), price);
    }

    function testFuzz_PlaceBid_NeverAcceptsBelowReserve(uint96 rawBid) public {
        uint256 bid = bound(uint256(rawBid), 0, 2 ether);
        vm.prank(seller);
        uint256 auctionId = auction.createAuction(address(nft), tokenId, 1 ether, 0.1 ether, 0, 1 days);
        if (bid < 1 ether) {
            vm.deal(buyer, bid);
            vm.prank(buyer);
            vm.expectRevert(IAuction.BidTooLow.selector);
            auction.placeBid{ value: bid }(auctionId);
            return;
        }
        vm.deal(buyer, bid);
        vm.prank(buyer);
        auction.placeBid{ value: bid }(auctionId);
        assertEq(auction.getAuction(auctionId).highestBid, bid);
        assertEq(auction.getAuction(auctionId).highestBidder, buyer);
    }
}

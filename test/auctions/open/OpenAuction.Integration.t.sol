// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../../support/TestBase.sol";

contract OpenAuctionIntegrationTest is ProtocolTestBase {
    OpenAuction internal auction;
    uint256 internal tokenId;

    function setUp() public {
        _setUpCore();
        auction = _deployOpenAuction(address(treasury));
        tokenId = _mint(nft, seller);
        vm.prank(seller);
        nft.approve(address(auction), tokenId);
        vm.prank(admin);
        treasury.setAuthorizedPayer(address(auction), true);
    }

    function test_SettlementCreditsTreasuryAndReleasesNFT() public {
        vm.prank(seller);
        uint256 auctionId = auction.createAuction(address(nft), tokenId, 1 ether, 0.1 ether, 0, 1 days);

        vm.deal(buyer, 2 ether);
        vm.prank(buyer);
        auction.placeBid{ value: 1 ether }(auctionId);
        vm.warp(block.timestamp + 1 days + 1);
        auction.finalizeAuction(auctionId);

        assertEq(nft.ownerOf(tokenId), buyer);
        assertEq(treasury.claimable(seller), 0.975 ether);
        assertEq(treasury.claimable(feeRecipient), 0.025 ether);
        assertEq(auction.totalActiveBidLiability(), 0);
    }

    function test_RefundLiabilityTransfersFromActiveBidToRefundClaim() public {
        vm.prank(seller);
        uint256 auctionId = auction.createAuction(address(nft), tokenId, 1 ether, 0.1 ether, 0, 1 days);

        vm.deal(buyer, 3 ether);
        vm.prank(buyer);
        auction.placeBid{ value: 1 ether }(auctionId);
        vm.deal(buyer2, 3 ether);
        vm.prank(buyer2);
        auction.placeBid{ value: 1.1 ether }(auctionId);

        assertEq(auction.totalActiveBidLiability(), 1.1 ether);
        assertEq(auction.totalRefundLiability(), 1 ether);
        assertEq(address(auction).balance, 2.1 ether);

        vm.prank(buyer);
        auction.withdrawRefund();
        assertEq(auction.totalRefundLiability(), 0);
        assertEq(address(auction).balance, 1.1 ether);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../../support/TestBase.sol";

contract DutchAuctionIntegrationTest is ProtocolTestBase {
    DutchAuction internal auction;
    uint256 internal tokenId;

    function setUp() public {
        _setUpCore();
        auction = _deployDutchAuction(address(treasury));
        vm.prank(admin);
        treasury.setAuthorizedPayer(address(auction), true);
        tokenId = _mint(nft, seller);
        vm.prank(seller);
        nft.approve(address(auction), tokenId);
    }

    function test_BuySettlesFeeAndSellerProceedsThroughTreasury() public {
        vm.prank(seller);
        uint256 id = auction.createAuction(address(nft), tokenId, 2 ether, 1 ether, 0, 1 days);
        vm.deal(buyer, 2 ether);
        vm.prank(buyer);
        auction.buy{ value: 2 ether }(id);

        assertEq(nft.ownerOf(tokenId), buyer);
        assertEq(treasury.claimable(feeRecipient), 0.05 ether);
        assertEq(treasury.claimable(seller), 1.95 ether);
        assertEq(address(auction).balance, 0);
    }

    function test_ExpiryReleasesNFTWithoutPayment() public {
        vm.prank(seller);
        uint256 id = auction.createAuction(address(nft), tokenId, 2 ether, 1 ether, 0, 1 days);
        vm.warp(block.timestamp + 1 days);
        auction.expireAuction(id);

        assertEq(nft.ownerOf(tokenId), seller);
        assertEq(address(auction).balance, 0);
    }
}

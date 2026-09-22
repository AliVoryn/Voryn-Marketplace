// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../support/TestBase.sol";

contract MarketplaceIntegrationTest is ProtocolTestBase {
    Marketplace internal marketplace;

    function setUp() public {
        _setUpCore();
        marketplace = _deployMarketplaceProxy(address(treasury), address(paymentManager));
        vm.prank(admin);
        treasury.setAuthorizedPayer(address(marketplace), true);
        vm.prank(admin);
        paymentManager.setCreditor(address(marketplace), true);
    }

    function test_MarketplaceSaleWiresNFTTreasuryAndPaymentManager() public {
        uint256 tokenId = _mint(nft, seller);
        vm.prank(seller);
        nft.approve(address(marketplace), tokenId);
        vm.prank(seller);
        uint256 listingId = marketplace.createListing(address(nft), tokenId, 1 ether, 0);
        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        marketplace.buy{ value: 1 ether }(listingId);
        assertEq(nft.ownerOf(tokenId), buyer);
        assertEq(treasury.claimable(seller), 0.975 ether);
        assertEq(treasury.claimable(feeRecipient), 0.025 ether);
        assertEq(paymentManager.totalClaimable(), 0);
    }

    function test_OfferCancellationUsesPaymentManagerAsRefundRail() public {
        uint256 tokenId = _mint(nft, seller);
        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        uint256 offerId =
            marketplace.makeOffer{ value: 1 ether }(address(nft), tokenId, uint64(block.timestamp + 1 days));
        vm.prank(buyer);
        marketplace.cancelOffer(offerId);
        assertEq(marketplace.totalOfferEscrow(), 0);
        assertEq(paymentManager.claimable(buyer), 1 ether);
        vm.prank(buyer);
        paymentManager.withdraw();
        assertEq(paymentManager.totalClaimable(), 0);
    }

    function test_AcceptOfferMovesNFTAndSplitsProceeds() public {
        uint256 tokenId = _mint(nft, seller);
        vm.prank(seller);
        nft.approve(address(marketplace), tokenId);
        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        uint256 offerId =
            marketplace.makeOffer{ value: 1 ether }(address(nft), tokenId, uint64(block.timestamp + 1 days));
        vm.prank(seller);
        marketplace.acceptOffer(offerId);
        assertEq(nft.ownerOf(tokenId), buyer);
        assertEq(treasury.claimable(seller), 0.975 ether);
        assertEq(treasury.claimable(feeRecipient), 0.025 ether);
        assertEq(marketplace.totalOfferEscrow(), 0);
    }
}

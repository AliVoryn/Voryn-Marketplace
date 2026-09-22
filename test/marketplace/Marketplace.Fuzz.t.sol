// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../support/TestBase.sol";

contract MarketplaceFuzzTest is ProtocolTestBase {
    Marketplace internal marketplace;

    function setUp() public {
        _setUpCore();
        marketplace = _deployMarketplaceProxy(address(treasury), address(paymentManager));
        vm.prank(admin);
        treasury.setAuthorizedPayer(address(marketplace), true);
        vm.prank(admin);
        paymentManager.setCreditor(address(marketplace), true);
    }

    function testFuzz_Buy_SellerReceivesConfiguredEffectiveFee(uint96 rawPrice) public {
        uint256 price = bound(uint256(rawPrice), 1, 20 ether);
        uint256 tokenId = _mint(nft, seller);
        vm.prank(seller);
        nft.approve(address(marketplace), tokenId);
        vm.prank(seller);
        uint256 listingId = marketplace.createListing(address(nft), tokenId, price, 0);
        vm.deal(buyer, price);
        vm.prank(buyer);
        marketplace.buy{ value: price }(listingId);
        uint256 effectiveBps = marketplace.protocolFeeBps() < marketplace.minimumFeeBps()
            ? marketplace.minimumFeeBps()
            : marketplace.protocolFeeBps();
        uint256 fee = price * effectiveBps / 10_000;
        assertEq(treasury.claimable(seller), price - fee);
        assertEq(treasury.claimable(feeRecipient), fee);
        assertEq(nft.ownerOf(tokenId), buyer);
    }

    function testFuzz_MakeOffer_TracksExactEscrow(uint96 rawAmount) public {
        uint256 amount = bound(uint256(rawAmount), 1, 20 ether);
        uint256 tokenId = _mint(nft, seller);
        vm.deal(buyer, amount);
        vm.prank(buyer);
        uint256 offerId =
            marketplace.makeOffer{ value: amount }(address(nft), tokenId, uint64(block.timestamp + 1 days));
        assertEq(marketplace.totalOfferEscrow(), amount);
        assertEq(marketplace.getOffer(offerId).amount, amount);
    }

    function testFuzz_InvalidateNonceAlwaysAdvances(uint32 times) public {
        uint256 n = bound(uint256(times), 1, 10);
        for (uint256 i; i < n; ++i) {
            vm.prank(seller);
            marketplace.invalidateNonce();
        }
        assertEq(marketplace.nonceOf(seller), n);
    }
}

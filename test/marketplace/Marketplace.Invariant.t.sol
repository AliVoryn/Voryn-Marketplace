// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import "forge-std/StdInvariant.sol";

import "../support/TestBase.sol";

contract MarketplaceInvariantHandler is Test {
    Marketplace internal marketplace;
    CustomNFT internal nft;
    uint256 public latestOfferId;

    constructor(Marketplace marketplace_, CustomNFT nft_) {
        marketplace = marketplace_;
        nft = nft_;
    }

    function createOffer(uint256 amountSeed, uint256 ttlSeed) external {
        uint256 amount = bound(amountSeed, 1 wei, 5 ether);
        uint64 ttl = uint64(bound(ttlSeed, 1 minutes, 7 days));
        uint64 expiresAt = uint64(block.timestamp + ttl);
        vm.deal(address(this), amount);
        latestOfferId = marketplace.makeOffer{ value: amount }(address(nft), 1, expiresAt);
    }

    function cancelLatestOffer() external {
        if (latestOfferId == 0) return;
        IMarketplace.Offer memory offer = marketplace.getOffer(latestOfferId);
        if (offer.status != IMarketplace.OfferStatus.Active || offer.buyer != address(this)) return;
        marketplace.cancelOffer(latestOfferId);
    }

    function expireLatestOffer() external {
        if (latestOfferId == 0) return;
        IMarketplace.Offer memory offer = marketplace.getOffer(latestOfferId);
        if (offer.status != IMarketplace.OfferStatus.Active) return;
        if (block.timestamp < offer.expiresAt) vm.warp(offer.expiresAt);
        marketplace.expireOffer(latestOfferId);
    }
}

contract MarketplaceInvariantTest is ProtocolTestBase {
    Marketplace internal marketplace;
    MarketplaceInvariantHandler internal handler;

    function setUp() public {
        _setUpCore();
        marketplace = _deployMarketplaceProxy(address(treasury), address(paymentManager));
        vm.prank(admin);
        treasury.setAuthorizedPayer(address(marketplace), true);
        vm.prank(admin);
        paymentManager.setCreditor(address(marketplace), true);
        handler = new MarketplaceInvariantHandler(marketplace, nft);
        targetContract(address(handler));
    }

    function invariant_OfferEscrowNeverExceedsMarketplaceBalance() public view {
        assertGe(address(marketplace).balance, marketplace.totalOfferEscrow());
    }
}

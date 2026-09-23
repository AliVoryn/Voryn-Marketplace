// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import "../support/TestBase.sol";

contract MarketplaceListingTest is ProtocolTestBase {
    Marketplace internal marketplace;
    uint256 internal tokenId;

    function setUp() public {
        _setUpCore();
        marketplace = _deployMarketplaceProxy(address(treasury), address(paymentManager));
        vm.prank(admin);
        treasury.setAuthorizedPayer(address(marketplace), true);
        vm.prank(admin);
        paymentManager.setCreditor(address(marketplace), true);
        tokenId = _mint(nft, seller);
        vm.prank(seller);
        nft.approve(address(marketplace), tokenId);
    }

    function test_CreateListing_RevertsIfCallerDoesNotOwnToken() public {
        vm.prank(attacker);
        vm.expectRevert(IMarketplace.NotListingOwner.selector);
        marketplace.createListing(address(nft), tokenId, 1 ether, 0);
    }

    function test_CreateListing_DefaultsExpiryToSevenDays() public {
        vm.prank(seller);
        uint256 listingId = marketplace.createListing(address(nft), tokenId, 1 ether, 0);
        IMarketplace.Listing memory l = marketplace.getListing(listingId);
        assertEq(l.expiresAt, block.timestamp + 7 days);
    }

    function test_CreateListing_RejectsInvalidArguments() public {
        vm.prank(seller);
        vm.expectRevert(IMarketplace.ZeroAddress.selector);
        marketplace.createListing(address(0), tokenId, 1 ether, 0);
        vm.prank(seller);
        vm.expectRevert(IMarketplace.InvalidPrice.selector);
        marketplace.createListing(address(nft), tokenId, 0, 0);
        vm.prank(seller);
        vm.expectRevert(IMarketplace.InvalidExpiry.selector);
        marketplace.createListing(address(nft), tokenId, 1 ether, uint64(block.timestamp));
    }

    function test_UpdateListing_ChangesPriceAndExpiry() public {
        vm.prank(seller);
        uint256 listingId = marketplace.createListing(address(nft), tokenId, 1 ether, 0);
        vm.prank(seller);
        marketplace.updateListing(listingId, 2 ether, uint64(block.timestamp + 2 days));
        IMarketplace.Listing memory listing = marketplace.getListing(listingId);
        assertEq(listing.price, 2 ether);
        assertEq(listing.expiresAt, block.timestamp + 2 days);
    }

    function test_UpdateListing_RejectsInvalidStateAndInputs() public {
        vm.prank(seller);
        uint256 listingId = marketplace.createListing(address(nft), tokenId, 1 ether, 0);
        vm.prank(attacker);
        vm.expectRevert(IMarketplace.NotListingOwner.selector);
        marketplace.updateListing(listingId, 2 ether, 0);
        vm.prank(seller);
        marketplace.updateListing(listingId, 2 ether, 0);
        assertEq(marketplace.getListing(listingId).expiresAt, block.timestamp + marketplace.DEFAULT_LISTING_TTL());
        vm.prank(seller);
        vm.expectRevert(IMarketplace.InvalidPrice.selector);
        marketplace.updateListing(listingId, 0, 0);
        vm.prank(seller);
        vm.expectRevert(IMarketplace.InvalidExpiry.selector);
        marketplace.updateListing(listingId, 2 ether, uint64(block.timestamp));
        vm.prank(seller);
        marketplace.cancelListing(listingId);
        vm.prank(seller);
        vm.expectRevert(IMarketplace.ListingNotActive.selector);
        marketplace.updateListing(listingId, 2 ether, 0);
    }

    function test_CancelListings_HandlesBatchAndBounds() public {
        vm.prank(seller);
        uint256 first = marketplace.createListing(address(nft), tokenId, 1 ether, 0);
        vm.prank(seller);
        uint256 second = marketplace.createListing(address(nft), tokenId, 2 ether, 0);
        uint256[] memory ids = new uint256[](2);
        ids[0] = first;
        ids[1] = second;
        vm.prank(seller);
        marketplace.cancelListings(ids);
        assertEq(uint8(marketplace.getListing(first).status), uint8(IMarketplace.ListingStatus.Cancelled));
        uint256[] memory empty;
        vm.prank(seller);
        vm.expectRevert(IMarketplace.BatchTooLarge.selector);
        marketplace.cancelListings(empty);
    }

    function test_ExpireListing_RequiresPastExpiry() public {
        vm.prank(seller);
        uint256 listingId = marketplace.createListing(address(nft), tokenId, 1 ether, uint64(block.timestamp + 1));
        vm.expectRevert(IMarketplace.ListingPastExpiry.selector);
        marketplace.expireListing(listingId);
        vm.warp(block.timestamp + 2);
        marketplace.expireListing(listingId);
        assertEq(uint8(marketplace.getListing(listingId).status), uint8(IMarketplace.ListingStatus.Expired));
    }

    function test_Buy_RequiresExactPrice() public {
        vm.prank(seller);
        uint256 listingId = marketplace.createListing(address(nft), tokenId, 1 ether, 0);
        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        vm.expectRevert(IMarketplace.InsufficientValue.selector);
        marketplace.buy{ value: 0.5 ether }(listingId);
    }

    function test_Buy_TransfersNFTAndSplitsProceeds() public {
        vm.prank(seller);
        uint256 listingId = marketplace.createListing(address(nft), tokenId, 1 ether, 0);
        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        marketplace.buy{ value: 1 ether }(listingId);
        assertEq(nft.ownerOf(tokenId), buyer);
        assertEq(treasury.claimable(seller), 0.975 ether);
    }

    function test_Buy_RevertsOnExpiredListing() public {
        vm.prank(seller);
        uint256 listingId = marketplace.createListing(address(nft), tokenId, 1 ether, uint64(block.timestamp + 1));
        vm.warp(block.timestamp + 2);
        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        vm.expectRevert(IMarketplace.ListingPastExpiry.selector);
        marketplace.buy{ value: 1 ether }(listingId);
    }

    function test_CancelListing_OnlySeller() public {
        vm.prank(seller);
        uint256 listingId = marketplace.createListing(address(nft), tokenId, 1 ether, 0);
        vm.prank(attacker);
        vm.expectRevert(IMarketplace.NotListingOwner.selector);
        marketplace.cancelListing(listingId);
    }

    function test_MakeOffer_EscrowsFunds() public {
        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        uint256 offerId =
            marketplace.makeOffer{ value: 1 ether }(address(nft), tokenId, uint64(block.timestamp + 1 days));
        assertEq(marketplace.totalOfferEscrow(), 1 ether);
        assertEq(marketplace.getOffer(offerId).amount, 1 ether);
        _assertOfferSolvent();
    }

    function test_MakeOffer_RejectsInvalidArguments() public {
        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        vm.expectRevert(IMarketplace.ZeroAddress.selector);
        marketplace.makeOffer{ value: 1 ether }(address(0), tokenId, uint64(block.timestamp + 1 days));
        vm.prank(buyer);
        vm.expectRevert(IMarketplace.InvalidPrice.selector);
        marketplace.makeOffer{ value: 0 }(address(nft), tokenId, uint64(block.timestamp + 1 days));
        vm.prank(buyer);
        vm.expectRevert(IMarketplace.InvalidExpiry.selector);
        marketplace.makeOffer{ value: 1 ether }(address(nft), tokenId, uint64(block.timestamp));
    }

    function test_OfferTransitionsRejectWrongCallersAndRepeatedCalls() public {
        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        uint256 offerId =
            marketplace.makeOffer{ value: 1 ether }(address(nft), tokenId, uint64(block.timestamp + 1 days));
        vm.prank(attacker);
        vm.expectRevert(IMarketplace.NotOfferOwner.selector);
        marketplace.cancelOffer(offerId);
        vm.prank(seller);
        marketplace.rejectOffer(offerId);
        vm.prank(seller);
        vm.expectRevert(IMarketplace.OfferNotActive.selector);
        marketplace.rejectOffer(offerId);
        vm.prank(buyer);
        vm.expectRevert(IMarketplace.OfferNotActive.selector);
        marketplace.cancelOffer(offerId);
    }

    function test_CancelOffer_RefundsViaPaymentManager() public {
        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        uint256 offerId =
            marketplace.makeOffer{ value: 1 ether }(address(nft), tokenId, uint64(block.timestamp + 1 days));
        vm.prank(buyer);
        marketplace.cancelOffer(offerId);
        assertEq(paymentManager.claimable(buyer), 1 ether);
        assertEq(marketplace.totalOfferEscrow(), 0);
        _assertOfferSolvent();
    }

    function test_AcceptOffer_RequiresCallerOwnsToken() public {
        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        uint256 offerId =
            marketplace.makeOffer{ value: 1 ether }(address(nft), tokenId, uint64(block.timestamp + 1 days));
        vm.prank(attacker);
        vm.expectRevert(IMarketplace.NotListingOwner.selector);
        marketplace.acceptOffer(offerId);
    }

    function test_AcceptOffer_TransfersNFTAndCreditsTreasury() public {
        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        uint256 offerId =
            marketplace.makeOffer{ value: 1 ether }(address(nft), tokenId, uint64(block.timestamp + 1 days));
        vm.prank(seller);
        marketplace.acceptOffer(offerId);
        assertEq(nft.ownerOf(tokenId), buyer);
        assertEq(treasury.claimable(seller), 0.975 ether);
        _assertOfferSolvent();
    }

    function test_RejectOffer_RefundsBuyerNotSeller() public {
        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        uint256 offerId =
            marketplace.makeOffer{ value: 1 ether }(address(nft), tokenId, uint64(block.timestamp + 1 days));
        vm.prank(seller);
        marketplace.rejectOffer(offerId);
        assertEq(paymentManager.claimable(buyer), 1 ether);
        _assertOfferSolvent();
    }

    function test_ExpireOffer_RequiresPastDeadline() public {
        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        uint256 offerId =
            marketplace.makeOffer{ value: 1 ether }(address(nft), tokenId, uint64(block.timestamp + 1 days));
        vm.expectRevert(IMarketplace.OfferPastExpiry.selector);
        marketplace.expireOffer(offerId);
        vm.warp(block.timestamp + 1 days + 1);
        marketplace.expireOffer(offerId);
        _assertOfferSolvent();
    }

    function test_CancelListing_RevertsAfterExpiry() public {
        vm.prank(seller);
        uint256 listingId = marketplace.createListing(address(nft), tokenId, 1 ether, uint64(block.timestamp + 1 days));
        vm.warp(block.timestamp + 1 days);
        vm.prank(seller);
        vm.expectRevert(IMarketplace.ListingPastExpiry.selector);
        marketplace.cancelListing(listingId);
        assertEq(uint8(marketplace.getListing(listingId).status), uint8(IMarketplace.ListingStatus.Active));
    }

    function test_AdminConfigurationAndPauseBoundaries() public {
        vm.prank(admin);
        marketplace.setTreasury(address(treasury));
        vm.prank(admin);
        marketplace.setPaymentManager(address(paymentManager));
        vm.prank(admin);
        marketplace.setProtocolFee(0);
        vm.prank(admin);
        marketplace.setMinimumFeeBps(1000);
        vm.prank(admin);
        marketplace.setCustomFee(seller, 500, true);
        vm.prank(admin);
        vm.expectRevert(IMarketplace.InvalidBps.selector);
        marketplace.setProtocolFee(1001);
        vm.prank(admin);
        marketplace.pause();
        vm.prank(seller);
        vm.expectRevert();
        marketplace.createListing(address(nft), tokenId, 1 ether, 0);
        vm.prank(admin);
        marketplace.unpause();
    }

    function test_ViewFunctionsAndNonceInvalidation() public {
        (string memory name_, string memory version_) = marketplace.domainInfo();
        assertEq(name_, "Professional Marketplace");
        assertEq(version_, "1");
        assertEq(marketplace.version(), 2);
        assertEq(marketplace.listingCount(), 0);
        assertEq(marketplace.offerCount(), 0);
        assertEq(marketplace.nonceOf(seller), 0);
        vm.prank(seller);
        marketplace.invalidateNonce();
        assertEq(marketplace.nonceOf(seller), 1);
    }

    function _assertOfferSolvent() internal view {
        assertGe(address(marketplace).balance, marketplace.totalOfferEscrow());
    }

    function test_Initialize_RevertsForEachZeroAddress() public {
        Marketplace impl = new Marketplace();
        vm.expectRevert(IMarketplace.ZeroAddress.selector);
        new ERC1967Proxy(
            address(impl),
            abi.encodeCall(Marketplace.initialize, (address(0), address(treasury), address(paymentManager)))
        );
        vm.expectRevert(IMarketplace.ZeroAddress.selector);
        new ERC1967Proxy(
            address(impl), abi.encodeCall(Marketplace.initialize, (admin, address(0), address(paymentManager)))
        );
        vm.expectRevert(IMarketplace.ZeroAddress.selector);
        new ERC1967Proxy(address(impl), abi.encodeCall(Marketplace.initialize, (admin, address(treasury), address(0))));
    }

    function test_Buy_RevertsWhenSellerNoLongerOwnsAsset() public {
        vm.prank(seller);
        uint256 listingId = marketplace.createListing(address(nft), tokenId, 1 ether, 0);
        vm.prank(seller);
        nft.transferFrom(seller, buyer2, tokenId);
        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        vm.expectRevert(IMarketplace.SellerNoLongerOwnsAsset.selector);
        marketplace.buy{ value: 1 ether }(listingId);
    }

    function test_UpdateListing_RevertsWhenSellerNoLongerOwnsAsset() public {
        vm.prank(seller);
        uint256 listingId = marketplace.createListing(address(nft), tokenId, 1 ether, 0);
        vm.prank(seller);
        nft.transferFrom(seller, buyer2, tokenId);
        vm.prank(seller);
        vm.expectRevert(IMarketplace.SellerNoLongerOwnsAsset.selector);
        marketplace.updateListing(listingId, 2 ether, 0);
    }

    function test_AcceptOffer_RevertsPastExpiry() public {
        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        uint256 offerId =
            marketplace.makeOffer{ value: 1 ether }(address(nft), tokenId, uint64(block.timestamp + 1 days));
        vm.warp(block.timestamp + 1 days + 1);
        vm.prank(seller);
        vm.expectRevert(IMarketplace.OfferPastExpiry.selector);
        marketplace.acceptOffer(offerId);
    }

    function test_RejectOffer_RevertsForNonTokenOwner() public {
        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        uint256 offerId =
            marketplace.makeOffer{ value: 1 ether }(address(nft), tokenId, uint64(block.timestamp + 1 days));
        vm.prank(attacker);
        vm.expectRevert(IMarketplace.NotListingOwner.selector);
        marketplace.rejectOffer(offerId);
    }

    function test_ExpireOffer_RevertsWhenNotActive() public {
        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        uint256 offerId =
            marketplace.makeOffer{ value: 1 ether }(address(nft), tokenId, uint64(block.timestamp + 1 days));
        vm.prank(buyer);
        marketplace.cancelOffer(offerId);
        vm.expectRevert(IMarketplace.OfferNotActive.selector);
        marketplace.expireOffer(offerId);
    }

    function test_CustomFee_RevertsAboveMaxBpsAndAppliesOverride() public {
        vm.prank(admin);
        vm.expectRevert(IMarketplace.InvalidBps.selector);
        marketplace.setCustomFee(seller, 1001, true);

        vm.prank(admin);
        marketplace.setCustomFee(seller, 500, true);
        vm.prank(seller);
        uint256 listingId = marketplace.createListing(address(nft), tokenId, 1 ether, 0);
        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        marketplace.buy{ value: 1 ether }(listingId);

        assertEq(treasury.claimable(seller), 0.95 ether);
    }

    function test_EffectiveFee_FallsBackToMinimumWhenProtocolFeeIsLower() public {
        vm.prank(admin);
        marketplace.setProtocolFee(0);
        vm.prank(admin);
        marketplace.setMinimumFeeBps(300);
        vm.prank(seller);
        uint256 listingId = marketplace.createListing(address(nft), tokenId, 1 ether, 0);
        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        marketplace.buy{ value: 1 ether }(listingId);

        assertEq(treasury.claimable(seller), 0.97 ether);
    }

    function test_SetTreasuryAndPaymentManager_RevertForZeroAddressAndNonAdmin() public {
        vm.prank(attacker);
        vm.expectRevert();
        marketplace.setTreasury(address(treasury));
        vm.prank(admin);
        vm.expectRevert(IMarketplace.ZeroAddress.selector);
        marketplace.setTreasury(address(0));
        vm.prank(admin);
        vm.expectRevert(IMarketplace.ZeroAddress.selector);
        marketplace.setPaymentManager(address(0));
    }

    function test_Pause_RevertsForNonOperator() public {
        vm.prank(attacker);
        vm.expectRevert();
        marketplace.pause();
    }

    function test_SetTreasury_RequiresMarketplaceAuthorization() public {
        Treasury alternate = new Treasury(admin, feeRecipient, address(0));
        vm.prank(admin);
        vm.expectRevert(IMarketplace.TreasuryNotAuthorized.selector);
        marketplace.setTreasury(address(alternate));
        vm.prank(admin);
        alternate.setAuthorizedPayer(address(marketplace), true);
        vm.prank(admin);
        marketplace.setTreasury(address(alternate));
        assertEq(marketplace.treasury(), address(alternate));
    }

    function test_SetPaymentManager_RequiresMarketplaceAuthorization() public {
        PaymentManager alternate = new PaymentManager(admin, address(0));
        vm.prank(admin);
        vm.expectRevert(IMarketplace.PaymentManagerNotAuthorized.selector);
        marketplace.setPaymentManager(address(alternate));
        vm.prank(admin);
        alternate.setCreditor(address(marketplace), true);
        vm.prank(admin);
        marketplace.setPaymentManager(address(alternate));
        assertEq(marketplace.paymentManager(), address(alternate));
    }

    function test_CreateListing_RejectsNonContractNFT() public {
        vm.prank(seller);
        vm.expectRevert(IMarketplace.UnsupportedAsset.selector);
        marketplace.createListing(address(0xBEEF), 1, 1 ether, 0);
    }

    function test_DefaultExpiry_RevertsWhenTimestampCannotFitUint64() public {
        vm.prank(seller);
        uint256 listingId = marketplace.createListing(address(nft), tokenId, 1 ether, 0);
        vm.warp(uint256(type(uint64).max) - 1 days);
        vm.prank(seller);
        vm.expectRevert(IMarketplace.InvalidExpiry.selector);
        marketplace.createListing(address(nft), tokenId, 1 ether, 0);
        vm.prank(seller);
        vm.expectRevert(IMarketplace.InvalidExpiry.selector);
        marketplace.updateListing(listingId, 2 ether, 0);
    }

    function test_CancelListings_AcceptsMaximumBatchAndRejectsOversizedBatch() public {
        uint256 max = marketplace.MAX_BATCH_CANCEL();
        uint256[] memory ids = new uint256[](max);
        for (uint256 i; i < max; ++i) {
            vm.prank(seller);
            ids[i] = marketplace.createListing(address(nft), tokenId, 1 ether, 0);
        }
        vm.prank(seller);
        marketplace.cancelListings(ids);
        assertEq(uint8(marketplace.getListing(ids[max - 1]).status), uint8(IMarketplace.ListingStatus.Cancelled));
        uint256[] memory oversized = new uint256[](max + 1);
        vm.prank(seller);
        vm.expectRevert(IMarketplace.BatchTooLarge.selector);
        marketplace.cancelListings(oversized);
    }

    function test_CancelListings_RevertsForForeignInactiveAndStaleEntries() public {
        vm.prank(seller);
        uint256 first = marketplace.createListing(address(nft), tokenId, 1 ether, 0);
        vm.prank(seller);
        uint256 second = marketplace.createListing(address(nft), tokenId, 2 ether, uint64(block.timestamp + 1 hours));
        uint256[] memory ids = new uint256[](1);
        ids[0] = first;
        vm.prank(attacker);
        vm.expectRevert(IMarketplace.NotListingOwner.selector);
        marketplace.cancelListings(ids);

        vm.prank(seller);
        marketplace.cancelListing(first);
        vm.prank(seller);
        vm.expectRevert(IMarketplace.ListingNotActive.selector);
        marketplace.cancelListings(ids);

        ids[0] = second;
        vm.warp(block.timestamp + 1 hours);
        vm.prank(seller);
        vm.expectRevert(IMarketplace.ListingPastExpiry.selector);
        marketplace.cancelListings(ids);
    }

    function test_ExpireListing_RevertsForUnknownAndInactiveListings() public {
        vm.expectRevert(IMarketplace.ListingNotActive.selector);
        marketplace.expireListing(999);
        vm.prank(seller);
        uint256 listingId = marketplace.createListing(address(nft), tokenId, 1 ether, 0);
        vm.prank(seller);
        marketplace.cancelListing(listingId);
        vm.expectRevert(IMarketplace.ListingNotActive.selector);
        marketplace.expireListing(listingId);
    }

    function test_Buy_RevertsForUnknownCancelledAndSoldListings() public {
        vm.deal(buyer, 3 ether);
        vm.prank(buyer);
        vm.expectRevert(IMarketplace.ListingNotActive.selector);
        marketplace.buy{ value: 1 ether }(999);

        vm.prank(seller);
        uint256 listingId = marketplace.createListing(address(nft), tokenId, 1 ether, 0);
        vm.prank(seller);
        marketplace.cancelListing(listingId);
        vm.prank(buyer);
        vm.expectRevert(IMarketplace.ListingNotActive.selector);
        marketplace.buy{ value: 1 ether }(listingId);

        vm.prank(seller);
        uint256 soldId = marketplace.createListing(address(nft), tokenId, 1 ether, 0);
        vm.prank(buyer);
        marketplace.buy{ value: 1 ether }(soldId);
        vm.prank(buyer);
        vm.expectRevert(IMarketplace.ListingNotActive.selector);
        marketplace.buy{ value: 1 ether }(soldId);
    }

    function test_Buy_RevertsAtExactDefaultExpiry() public {
        vm.prank(seller);
        uint256 listingId = marketplace.createListing(address(nft), tokenId, 1 ether, 0);
        vm.warp(block.timestamp + marketplace.DEFAULT_LISTING_TTL());
        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        vm.expectRevert(IMarketplace.ListingPastExpiry.selector);
        marketplace.buy{ value: 1 ether }(listingId);
    }

    function test_MakeOffer_RejectsNonContractNFT() public {
        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        vm.expectRevert(IMarketplace.UnsupportedAsset.selector);
        marketplace.makeOffer{ value: 1 ether }(address(0xBEEF), 1, uint64(block.timestamp + 1 days));
    }

    function test_EnumerationViewsTrackListingsAndOffers() public {
        assertEq(marketplace.sellerListingCount(seller), 0);
        assertEq(marketplace.buyerOfferCount(buyer), 0);
        vm.prank(seller);
        uint256 listingId = marketplace.createListing(address(nft), tokenId, 1 ether, 0);
        vm.deal(buyer, 2 ether);
        vm.prank(buyer);
        uint256 firstOffer =
            marketplace.makeOffer{ value: 1 ether }(address(nft), tokenId, uint64(block.timestamp + 1 days));
        vm.prank(buyer);
        uint256 secondOffer =
            marketplace.makeOffer{ value: 1 ether }(address(nft), tokenId, uint64(block.timestamp + 2 days));
        assertEq(marketplace.sellerListingCount(seller), 1);
        assertEq(marketplace.sellerListingAt(seller, 0), listingId);
        assertEq(marketplace.buyerOfferCount(buyer), 2);
        assertEq(marketplace.buyerOfferAt(buyer, 0), firstOffer);
        assertEq(marketplace.buyerOfferAt(buyer, 1), secondOffer);
        assertEq(marketplace.listingCount(), 1);
        assertEq(marketplace.offerCount(), 2);
        assertEq(marketplace.totalOfferEscrow(), 2 ether);
        vm.expectRevert();
        marketplace.buyerOfferAt(buyer, 2);
        vm.expectRevert();
        marketplace.sellerListingAt(seller, 1);
    }

    function test_AdminSetters_RejectInvalidInputs() public {
        vm.startPrank(admin);
        vm.expectRevert(IMarketplace.InvalidBps.selector);
        marketplace.setMinimumFeeBps(1001);
        vm.expectRevert(IMarketplace.ZeroAddress.selector);
        marketplace.setCustomFee(address(0), 100, true);
        vm.expectRevert(IMarketplace.UnsupportedAsset.selector);
        marketplace.setTreasury(address(0xBEEF));
        vm.expectRevert(IMarketplace.UnsupportedAsset.selector);
        marketplace.setPaymentManager(address(0xBEEF));
        vm.stopPrank();
        Marketplace impl = new Marketplace();
        vm.expectRevert(IMarketplace.UnsupportedAsset.selector);
        new ERC1967Proxy(
            address(impl), abi.encodeCall(Marketplace.initialize, (admin, address(0xBEEF), address(paymentManager)))
        );
    }

    function test_FeeConfigurationEmitsEvents() public {
        vm.expectEmit(false, false, false, true, address(marketplace));
        emit IMarketplace.FeeConfigUpdated(400, 100);
        vm.prank(admin);
        marketplace.setProtocolFee(400);
        vm.expectEmit(true, false, false, true, address(marketplace));
        emit IMarketplace.CustomFeeUpdated(seller, 50, true);
        vm.prank(admin);
        marketplace.setCustomFee(seller, 50, true);
    }

    function test_ZeroEffectiveFee_SkipsFeeCreditAndPaysSellerInFull() public {
        vm.prank(admin);
        marketplace.setProtocolFee(0);
        vm.prank(admin);
        marketplace.setMinimumFeeBps(0);
        vm.prank(seller);
        uint256 listingId = marketplace.createListing(address(nft), tokenId, 1 ether, 0);
        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        marketplace.buy{ value: 1 ether }(listingId);
        assertEq(treasury.claimable(seller), 1 ether);
        assertEq(treasury.claimable(feeRecipient), 0);
        assertEq(treasury.totalLiabilities(), 1 ether);
    }

    function test_CustomFee_DisablingFallsBackToProtocolFeeAndZeroOverrideIsHonoured() public {
        vm.prank(admin);
        marketplace.setCustomFee(seller, 500, true);
        vm.prank(admin);
        marketplace.setCustomFee(seller, 500, false);
        vm.prank(seller);
        uint256 first = marketplace.createListing(address(nft), tokenId, 1 ether, 0);
        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        marketplace.buy{ value: 1 ether }(first);
        assertEq(treasury.claimable(seller), 0.975 ether);

        vm.prank(admin);
        marketplace.setCustomFee(buyer, 0, true);
        vm.prank(buyer);
        nft.approve(address(marketplace), tokenId);
        vm.prank(buyer);
        uint256 second = marketplace.createListing(address(nft), tokenId, 1 ether, 0);
        vm.deal(buyer2, 1 ether);
        vm.prank(buyer2);
        marketplace.buy{ value: 1 ether }(second);
        assertEq(treasury.claimable(buyer), 1 ether);
    }
}

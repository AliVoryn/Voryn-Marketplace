pragma solidity ^0.8.24;
import "../helpers/TestBase.sol";
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
        marketplace.buy{value: 0.5 ether}(listingId);
    }
    function test_Buy_TransfersNFTAndSplitsProceeds() public {
        vm.prank(seller);
        uint256 listingId = marketplace.createListing(address(nft), tokenId, 1 ether, 0);
        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        marketplace.buy{value: 1 ether}(listingId);
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
        marketplace.buy{value: 1 ether}(listingId);
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
        uint256 offerId = marketplace.makeOffer{value: 1 ether}(address(nft), tokenId, uint64(block.timestamp + 1 days));
        assertEq(marketplace.totalOfferEscrow(), 1 ether);
        assertEq(marketplace.getOffer(offerId).amount, 1 ether);
        _assertOfferSolvent();
    }
    function test_MakeOffer_RejectsInvalidArguments() public {
        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        vm.expectRevert(IMarketplace.ZeroAddress.selector);
        marketplace.makeOffer{value: 1 ether}(address(0), tokenId, uint64(block.timestamp + 1 days));
        vm.prank(buyer);
        vm.expectRevert(IMarketplace.InvalidPrice.selector);
        marketplace.makeOffer{value: 0}(address(nft), tokenId, uint64(block.timestamp + 1 days));
        vm.prank(buyer);
        vm.expectRevert(IMarketplace.InvalidExpiry.selector);
        marketplace.makeOffer{value: 1 ether}(address(nft), tokenId, uint64(block.timestamp));
    }
    function test_OfferTransitionsRejectWrongCallersAndRepeatedCalls() public {
        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        uint256 offerId = marketplace.makeOffer{value: 1 ether}(address(nft), tokenId, uint64(block.timestamp + 1 days));
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
        uint256 offerId = marketplace.makeOffer{value: 1 ether}(address(nft), tokenId, uint64(block.timestamp + 1 days));
        vm.prank(buyer);
        marketplace.cancelOffer(offerId);
        assertEq(paymentManager.claimable(buyer), 1 ether);
        assertEq(marketplace.totalOfferEscrow(), 0);
        _assertOfferSolvent();
    }
    function test_AcceptOffer_RequiresCallerOwnsToken() public {
        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        uint256 offerId = marketplace.makeOffer{value: 1 ether}(address(nft), tokenId, uint64(block.timestamp + 1 days));
        vm.prank(attacker);
        vm.expectRevert(IMarketplace.NotListingOwner.selector);
        marketplace.acceptOffer(offerId);
    }
    function test_AcceptOffer_TransfersNFTAndCreditsTreasury() public {
        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        uint256 offerId = marketplace.makeOffer{value: 1 ether}(address(nft), tokenId, uint64(block.timestamp + 1 days));
        vm.prank(seller);
        marketplace.acceptOffer(offerId);
        assertEq(nft.ownerOf(tokenId), buyer);
        assertEq(treasury.claimable(seller), 0.975 ether);
        _assertOfferSolvent();
    }
    function test_RejectOffer_RefundsBuyerNotSeller() public {
        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        uint256 offerId = marketplace.makeOffer{value: 1 ether}(address(nft), tokenId, uint64(block.timestamp + 1 days));
        vm.prank(seller);
        marketplace.rejectOffer(offerId);
        assertEq(paymentManager.claimable(buyer), 1 ether);
        _assertOfferSolvent();
    }
    function test_ExpireOffer_RequiresPastDeadline() public {
        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        uint256 offerId = marketplace.makeOffer{value: 1 ether}(address(nft), tokenId, uint64(block.timestamp + 1 days));
        vm.expectRevert(IMarketplace.OfferPastExpiry.selector);
        marketplace.expireOffer(offerId);
        vm.warp(block.timestamp + 1 days + 1);
        marketplace.expireOffer(offerId);
        _assertOfferSolvent();
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
        marketplace.customFeeManage(seller, 500, true);
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
}

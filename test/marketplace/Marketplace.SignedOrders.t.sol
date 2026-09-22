// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import "../support/TestBase.sol";

contract MarketplaceSignedOrdersTest is ProtocolTestBase {
    Marketplace internal marketplace;
    uint256 internal tokenId;
    uint256 internal sellerPk = 0xA11CE;
    address internal signerSeller;
    bytes32 internal constant EIP712_DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    bytes32 internal constant LISTING_TYPEHASH = keccak256(
        "ListingOrder(address seller,address nft,uint256 tokenId,uint256 price,uint64 expiresAt,uint256 nonce)"
    );

    function setUp() public {
        _setUpCore();
        marketplace = _deployMarketplaceProxy(address(treasury), address(paymentManager));
        vm.prank(admin);
        treasury.setAuthorizedPayer(address(marketplace), true);
        signerSeller = vm.addr(sellerPk);
        tokenId = _mint(nft, signerSeller);
        vm.prank(signerSeller);
        nft.approve(address(marketplace), tokenId);
    }

    function _domainSeparator() internal view returns (bytes32) {
        return keccak256(
            abi.encode(
                EIP712_DOMAIN_TYPEHASH,
                keccak256(bytes("Professional Marketplace")),
                keccak256(bytes("1")),
                block.chainid,
                address(marketplace)
            )
        );
    }

    function _sign(address seller_, address nft_, uint256 tokenId_, uint256 price, uint64 expiresAt, uint256 nonce)
        internal
        view
        returns (bytes memory sig)
    {
        bytes32 structHash = keccak256(abi.encode(LISTING_TYPEHASH, seller_, nft_, tokenId_, price, expiresAt, nonce));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", _domainSeparator(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(sellerPk, digest);
        sig = abi.encodePacked(r, s, v);
    }

    function test_hashListingOrder_MatchesOurOwnDomainReconstruction() public view {
        bytes32 fromContract = marketplace.hashListingOrder(
            signerSeller, address(nft), tokenId, 1 ether, uint64(block.timestamp + 1 days), 0
        );
        bytes32 structHash = keccak256(
            abi.encode(
                LISTING_TYPEHASH,
                signerSeller,
                address(nft),
                tokenId,
                1 ether,
                uint64(block.timestamp + 1 days),
                uint256(0)
            )
        );
        bytes32 expected = keccak256(abi.encodePacked("\x19\x01", _domainSeparator(), structHash));
        assertEq(
            fromContract,
            expected,
            "contract domain separator must match name/version/chainId/verifyingContract exactly"
        );
    }

    function test_ExecuteSignedListing_ValidSignature_Succeeds() public {
        uint64 expiresAt = uint64(block.timestamp + 1 days);
        bytes memory sig = _sign(signerSeller, address(nft), tokenId, 1 ether, expiresAt, 0);
        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        marketplace.executeSignedListing{ value: 1 ether }(
            signerSeller, address(nft), tokenId, 1 ether, expiresAt, 0, sig
        );
        assertEq(nft.ownerOf(tokenId), buyer);
    }

    function test_ExecuteSignedListing_RevertsOnReplay() public {
        uint64 expiresAt = uint64(block.timestamp + 1 days);
        bytes memory sig = _sign(signerSeller, address(nft), tokenId, 1 ether, expiresAt, 0);
        vm.deal(buyer, 2 ether);
        vm.prank(buyer);
        marketplace.executeSignedListing{ value: 1 ether }(
            signerSeller, address(nft), tokenId, 1 ether, expiresAt, 0, sig
        );
        vm.prank(buyer);
        vm.expectRevert(IMarketplace.InvalidNonce.selector);
        marketplace.executeSignedListing{ value: 1 ether }(
            signerSeller, address(nft), tokenId, 1 ether, expiresAt, 0, sig
        );
    }

    function test_ExecuteSignedListing_RevertsOnWrongSigner() public {
        uint64 expiresAt = uint64(block.timestamp + 1 days);
        uint256 wrongPk = 0xBEEF;
        bytes32 structHash = keccak256(
            abi.encode(LISTING_TYPEHASH, signerSeller, address(nft), tokenId, 1 ether, expiresAt, uint256(0))
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", _domainSeparator(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(wrongPk, digest);
        bytes memory badSig = abi.encodePacked(r, s, v);
        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        vm.expectRevert(IMarketplace.SignatureInvalid.selector);
        marketplace.executeSignedListing{ value: 1 ether }(
            signerSeller, address(nft), tokenId, 1 ether, expiresAt, 0, badSig
        );
    }

    function test_ExecuteSignedListing_RevertsOnExpiredDeadline() public {
        uint64 expiresAt = uint64(block.timestamp + 1);
        bytes memory sig = _sign(signerSeller, address(nft), tokenId, 1 ether, expiresAt, 0);
        vm.warp(block.timestamp + 2);
        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        vm.expectRevert(IMarketplace.InvalidSignatureDeadline.selector);
        marketplace.executeSignedListing{ value: 1 ether }(
            signerSeller, address(nft), tokenId, 1 ether, expiresAt, 0, sig
        );
    }

    function test_InvalidateNonce_InvalidatesOutstandingSignatures() public {
        uint64 expiresAt = uint64(block.timestamp + 1 days);
        bytes memory sig = _sign(signerSeller, address(nft), tokenId, 1 ether, expiresAt, 0);
        vm.prank(signerSeller);
        marketplace.invalidateNonce();
        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        vm.expectRevert(IMarketplace.InvalidNonce.selector);
        marketplace.executeSignedListing{ value: 1 ether }(
            signerSeller, address(nft), tokenId, 1 ether, expiresAt, 0, sig
        );
    }

    function test_ExecuteSignedListing_RevertsOnZeroAddressArgs() public {
        uint64 expiresAt = uint64(block.timestamp + 1 days);
        bytes memory sig = _sign(signerSeller, address(nft), tokenId, 1 ether, expiresAt, 0);
        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        vm.expectRevert(IMarketplace.ZeroAddress.selector);
        marketplace.executeSignedListing{ value: 1 ether }(
            address(0), address(nft), tokenId, 1 ether, expiresAt, 0, sig
        );
        vm.prank(buyer);
        vm.expectRevert(IMarketplace.ZeroAddress.selector);
        marketplace.executeSignedListing{ value: 1 ether }(
            signerSeller, address(0), tokenId, 1 ether, expiresAt, 0, sig
        );
    }

    function test_ExecuteSignedListing_RevertsOnZeroPrice() public {
        uint64 expiresAt = uint64(block.timestamp + 1 days);
        bytes memory sig = _sign(signerSeller, address(nft), tokenId, 0, expiresAt, 0);
        vm.prank(buyer);
        vm.expectRevert(IMarketplace.InvalidPrice.selector);
        marketplace.executeSignedListing(signerSeller, address(nft), tokenId, 0, expiresAt, 0, sig);
    }

    function test_ExecuteSignedListing_RevertsOnWrongPaymentValue() public {
        uint64 expiresAt = uint64(block.timestamp + 1 days);
        bytes memory sig = _sign(signerSeller, address(nft), tokenId, 1 ether, expiresAt, 0);
        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        vm.expectRevert(IMarketplace.InsufficientValue.selector);
        marketplace.executeSignedListing{ value: 0.5 ether }(
            signerSeller, address(nft), tokenId, 1 ether, expiresAt, 0, sig
        );
    }

    function test_ExecuteSignedListing_RevertsWhenSellerNoLongerOwnsAsset() public {
        uint64 expiresAt = uint64(block.timestamp + 1 days);
        bytes memory sig = _sign(signerSeller, address(nft), tokenId, 1 ether, expiresAt, 0);
        vm.prank(signerSeller);
        nft.transferFrom(signerSeller, buyer2, tokenId);
        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        vm.expectRevert(IMarketplace.SellerNoLongerOwnsAsset.selector);
        marketplace.executeSignedListing{ value: 1 ether }(
            signerSeller, address(nft), tokenId, 1 ether, expiresAt, 0, sig
        );
    }

    function test_ExecuteSignedListing_RevertsWhenBuyerIsSeller() public {
        uint64 expiresAt = uint64(block.timestamp + 1 days);
        bytes memory sig = _sign(signerSeller, address(nft), tokenId, 1 ether, expiresAt, 0);
        vm.deal(signerSeller, 1 ether);
        vm.prank(signerSeller);
        vm.expectRevert(IMarketplace.CannotBuyOwnListing.selector);
        marketplace.executeSignedListing{ value: 1 ether }(
            signerSeller, address(nft), tokenId, 1 ether, expiresAt, 0, sig
        );
    }

    function test_ExecuteSignedListing_RevertsForNonContractNFT() public {
        uint64 expiresAt = uint64(block.timestamp + 1 days);
        bytes memory sig = _sign(signerSeller, address(0xBEEF), tokenId, 1 ether, expiresAt, 0);
        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        vm.expectRevert(IMarketplace.UnsupportedAsset.selector);
        marketplace.executeSignedListing{ value: 1 ether }(
            signerSeller, address(0xBEEF), tokenId, 1 ether, expiresAt, 0, sig
        );
    }

    function test_ExecuteSignedListing_RejectsFutureNonce() public {
        uint64 expiresAt = uint64(block.timestamp + 1 days);
        bytes memory sig = _sign(signerSeller, address(nft), tokenId, 1 ether, expiresAt, 1);
        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        vm.expectRevert(IMarketplace.InvalidNonce.selector);
        marketplace.executeSignedListing{ value: 1 ether }(
            signerSeller, address(nft), tokenId, 1 ether, expiresAt, 1, sig
        );
    }

    function test_ExecuteSignedListing_RejectsTamperedPrice() public {
        uint64 expiresAt = uint64(block.timestamp + 1 days);
        bytes memory sig = _sign(signerSeller, address(nft), tokenId, 1 ether, expiresAt, 0);
        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        vm.expectRevert(IMarketplace.SignatureInvalid.selector);
        marketplace.executeSignedListing{ value: 0.5 ether }(
            signerSeller, address(nft), tokenId, 0.5 ether, expiresAt, 0, sig
        );
        assertEq(nft.ownerOf(tokenId), signerSeller);
    }

    function test_ExecuteSignedListing_RevertsWhilePaused() public {
        uint64 expiresAt = uint64(block.timestamp + 1 days);
        bytes memory sig = _sign(signerSeller, address(nft), tokenId, 1 ether, expiresAt, 0);
        vm.prank(admin);
        marketplace.pause();
        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        vm.expectRevert();
        marketplace.executeSignedListing{ value: 1 ether }(
            signerSeller, address(nft), tokenId, 1 ether, expiresAt, 0, sig
        );
    }

    function test_ExecuteSignedListing_AdvancesNonceSplitsFeeAndEmits() public {
        uint64 expiresAt = uint64(block.timestamp + 1 days);
        bytes memory sig = _sign(signerSeller, address(nft), tokenId, 1 ether, expiresAt, 0);
        bytes32 orderHash = marketplace.hashListingOrder(signerSeller, address(nft), tokenId, 1 ether, expiresAt, 0);
        vm.deal(buyer, 1 ether);
        vm.expectEmit(true, true, true, true, address(marketplace));
        emit IMarketplace.SignedListingExecuted(orderHash, signerSeller, buyer, address(nft), tokenId, 1 ether);
        vm.prank(buyer);
        bytes32 returnedHash = marketplace.executeSignedListing{ value: 1 ether }(
            signerSeller, address(nft), tokenId, 1 ether, expiresAt, 0, sig
        );
        assertEq(returnedHash, orderHash);
        assertEq(marketplace.nonceOf(signerSeller), 1);
        assertEq(treasury.claimable(signerSeller), 0.975 ether);
        assertEq(treasury.claimable(feeRecipient), 0.025 ether);
        assertEq(nft.ownerOf(tokenId), buyer);
    }
}

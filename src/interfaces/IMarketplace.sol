// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IMarketplace {
    enum ListingStatus {
        None,
        Active,
        Sold,
        Cancelled,
        Expired
    }
    enum OfferStatus {
        None,
        Active,
        Accepted,
        Cancelled,
        Rejected,
        Expired
    }

    struct Listing {
        uint256 id;
        address seller;
        address nft;
        uint256 tokenId;
        uint256 price;
        uint64 expiresAt;
        ListingStatus status;
    }

    struct Offer {
        uint256 id;
        address buyer;
        address nft;
        uint256 tokenId;
        uint256 amount;
        uint64 expiresAt;
        OfferStatus status;
    }

    event ListingCreated(
        uint256 indexed listingId,
        address indexed seller,
        address indexed nft,
        uint256 tokenId,
        uint256 price,
        uint64 expiresAt
    );
    event ListingUpdated(uint256 indexed listingId, uint256 price, uint64 expiresAt);
    event ListingCancelled(uint256 indexed listingId);
    event ListingExpired(uint256 indexed listingId);
    event ListingSold(uint256 indexed listingId, address indexed buyer, uint256 price);
    event OfferCreated(
        uint256 indexed offerId,
        address indexed buyer,
        address indexed nft,
        uint256 tokenId,
        uint256 amount,
        uint64 expiresAt
    );
    event OfferCancelled(uint256 indexed offerId);
    event OfferExpired(uint256 indexed offerId);
    event OfferAccepted(uint256 indexed offerId, address indexed seller, uint256 amount);
    event OfferRejected(uint256 indexed offerId);
    event FeeConfigUpdated(uint16 protocolFeeBps, uint16 minimumFeeBps);
    event CustomFeeUpdated(address indexed account, uint16 feeBps, bool enabled);
    event SignedListingExecuted(
        bytes32 indexed orderHash,
        address indexed seller,
        address indexed buyer,
        address nft,
        uint256 tokenId,
        uint256 price
    );
    event OrderNonceInvalidated(address indexed account, uint256 newNonce);
    event TreasuryUpdated(address indexed treasury);
    event PaymentManagerUpdated(address indexed paymentManager);

    error ZeroAddress();
    error InvalidPrice();
    error InvalidExpiry();
    error NotListingOwner();
    error ListingNotActive();
    error ListingPastExpiry();
    error NotOfferOwner();
    error OfferNotActive();
    error OfferPastExpiry();
    error InsufficientValue();
    error UnsupportedAsset();
    error TreasuryNotAuthorized();
    error PaymentManagerNotAuthorized();
    error InvalidBps();
    error InvalidNonce();
    error SignatureInvalid();
    error SellerNoLongerOwnsAsset();
    error CannotBuyOwnListing();
    error InvalidSignatureDeadline();
    error EscrowInvariantBroken();
    error BatchTooLarge();

    function createListing(address nft, uint256 tokenId, uint256 price, uint64 expiresAt)
        external
        returns (uint256 listingId);
    function updateListing(uint256 listingId, uint256 newPrice, uint64 newExpiresAt) external;
    function cancelListing(uint256 listingId) external;
    function cancelListings(uint256[] calldata listingIds) external;
    function expireListing(uint256 listingId) external;
    function buy(uint256 listingId) external payable;
    function makeOffer(address nft, uint256 tokenId, uint64 expiresAt) external payable returns (uint256 offerId);
    function cancelOffer(uint256 offerId) external;
    function expireOffer(uint256 offerId) external;
    function acceptOffer(uint256 offerId) external;
    function rejectOffer(uint256 offerId) external;
    function executeSignedListing(
        address seller,
        address nft,
        uint256 tokenId,
        uint256 price,
        uint64 expiresAt,
        uint256 nonce,
        bytes calldata signature
    ) external payable returns (bytes32 orderHash);
    function hashListingOrder(
        address seller,
        address nft,
        uint256 tokenId,
        uint256 price,
        uint64 expiresAt,
        uint256 nonce
    ) external view returns (bytes32);
    function invalidateNonce() external;
    function nonceOf(address account) external view returns (uint256);
    function getListing(uint256 listingId) external view returns (Listing memory);
    function getOffer(uint256 offerId) external view returns (Offer memory);
}

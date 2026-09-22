// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IMarketplace {
    enum ListingStatus { None, Active, Sold, Cancelled, Expired }
    enum OfferStatus { None, Active, Accepted, Cancelled, Rejected, Expired }

    struct Listing {
        uint id;
        address seller;
        address nft;
        uint tokenId;
        uint price;
        uint64 expiresAt;
        ListingStatus status;
    }

    struct Offer {
        uint id;
        address buyer;
        address nft;
        uint tokenId;
        uint amount;
        uint64 expiresAt;
        OfferStatus status;
    }

    event ListingCreated(uint indexed listingId, address indexed seller, address indexed nft, uint tokenId, uint price, uint64 expiresAt);
    event ListingUpdated(uint indexed listingId, uint price, uint64 expiresAt);
    event ListingCancelled(uint indexed listingId);
    event ListingExpired(uint indexed listingId);
    event ListingSold(uint indexed listingId, address indexed buyer, uint price);
    event OfferCreated(uint indexed offerId, address indexed buyer, address indexed nft, uint tokenId, uint amount, uint64 expiresAt);
    event OfferCancelled(uint indexed offerId);
    event OfferExpired(uint indexed offerId);
    event OfferAccepted(uint indexed offerId, address indexed seller, uint amount);
    event OfferRejected(uint indexed offerId);
    event FeeConfigUpdated(uint16 protocolFeeBps, uint16 minimumFeeBps);
    event CustomFeeUpdated(address indexed account, uint16 feeBps, bool enabled);
    event SignedListingExecuted(bytes32 indexed orderHash, address indexed seller, address indexed buyer, address nft, uint tokenId, uint price);
    event OrderNonceInvalidated(address indexed account, uint newNonce);
    event TreasuryUpdated(address indexed treasury);
    event PaymentManagerUpdated(address indexed paymentManager);
    event UpgradeAuthorized(address indexed implementation, address indexed authorizedBy);

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
    error InvalidBps();
    error InvalidNonce();
    error SignatureInvalid();
    error OrderAlreadyUsed();
    error SellerNoLongerOwnsAsset();
    error InvalidSignatureDeadline();
    error EscrowInvariantBroken();
    error SettlementFailed();
    error BatchTooLarge();

    function createListing(address nft, uint tokenId, uint price, uint64 expiresAt) external returns (uint listingId);
    function updateListing(uint listingId, uint newPrice, uint64 newExpiresAt) external;
    function cancelListing(uint listingId) external;
    function cancelListings(uint[] calldata listingIds) external;
    function expireListing(uint listingId) external;
    function buy(uint listingId) external payable;
    function makeOffer(address nft, uint tokenId, uint64 expiresAt) external payable returns (uint offerId);
    function cancelOffer(uint offerId) external;
    function expireOffer(uint offerId) external;
    function acceptOffer(uint offerId) external;
    function rejectOffer(uint offerId) external;
    function executeSignedListing(address seller, address nft, uint tokenId, uint price, uint64 expiresAt, uint nonce, bytes calldata signature) external payable returns (bytes32 orderHash);
    function hashListingOrder(address seller, address nft, uint tokenId, uint price, uint64 expiresAt, uint nonce) external view returns (bytes32);
    function invalidateNonce() external;
    function nonceOf(address account) external view returns (uint);
    function getListing(uint listingId) external view returns (Listing memory);
    function getOffer(uint offerId) external view returns (Offer memory);
}

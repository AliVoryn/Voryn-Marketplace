// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "../interfaces/IMarketplace.sol";
import "../interfaces/ICustomNFT.sol";
import "../interfaces/ITreasury.sol";
import "../interfaces/IPaymentManager.sol";
import "../libraries/FeeMath.sol";
import "../libraries/ListingMath.sol";
import "../libraries/OrderHashLib.sol";
import "../libraries/AutomationScanLib.sol";

contract Marketplace is
    Initializable,
    UUPSUpgradeable,
    AccessControlUpgradeable,
    PausableUpgradeable,
    EIP712Upgradeable,
    ReentrancyGuardUpgradeable,
    IMarketplace
{
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    uint64 public constant DEFAULT_LISTING_TTL = 7 days;
    uint16 public constant DEFAULT_PROTOCOL_FEE_BPS = 250;
    uint16 public constant DEFAULT_MINIMUM_FEE_BPS = 100;
    uint256 public constant MAX_BATCH_CANCEL = 50;
    bytes32 public constant LISTING_TYPEHASH = keccak256(
        "ListingOrder(address seller,address nft,uint256 tokenId,uint256 price,uint64 expiresAt,uint256 nonce)"
    );

    address public treasury;
    address public paymentManager;
    uint16 public protocolFeeBps;
    uint16 public minimumFeeBps;
    uint256 private nextListingId;
    uint256 private nextOfferId;
    uint256 public totalOfferEscrow;
    mapping(uint256 => Listing) private listings;
    mapping(uint256 => Offer) private offers;
    mapping(address => uint256[]) private sellerListings;
    mapping(address => uint256[]) private buyerOffers;
    mapping(address => uint256) public orderNonce;
    mapping(address => uint16) public customFeeBps;
    mapping(address => bool) public customFeeEnabled;

    constructor() {
        _disableInitializers();
    }

    function initialize(address admin, address treasury_, address paymentManager_) public initializer {
        if (admin == address(0) || treasury_ == address(0) || paymentManager_ == address(0)) revert ZeroAddress();
        if (treasury_.code.length == 0 || paymentManager_.code.length == 0) revert UnsupportedAsset();
        __AccessControl_init();
        __Pausable_init();
        __EIP712_init("Professional Marketplace", "1");
        __ReentrancyGuard_init();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ADMIN_ROLE, admin);
        _grantRole(OPERATOR_ROLE, admin);
        treasury = treasury_;
        paymentManager = paymentManager_;
        protocolFeeBps = DEFAULT_PROTOCOL_FEE_BPS;
        minimumFeeBps = DEFAULT_MINIMUM_FEE_BPS;
    }

    function createListing(address nft, uint256 tokenId, uint256 price, uint64 expiresAt)
        external
        override
        whenNotPaused
        returns (uint256 listingId)
    {
        listingId = _createListing(msg.sender, nft, tokenId, price, expiresAt);
    }

    function updateListing(uint256 listingId, uint256 newPrice, uint64 newExpiresAt) external override whenNotPaused {
        Listing storage item = listings[listingId];
        if (item.seller != msg.sender) revert NotListingOwner();
        if (item.status != ListingStatus.Active) revert ListingNotActive();
        if (newPrice == 0) revert InvalidPrice();
        if (newExpiresAt != 0 && newExpiresAt <= block.timestamp) revert InvalidExpiry();
        if (newExpiresAt == 0 && block.timestamp > type(uint64).max - DEFAULT_LISTING_TTL) revert InvalidExpiry();
        if (ICustomNFT(item.nft).ownerOf(item.tokenId) != item.seller) revert SellerNoLongerOwnsAsset();
        uint64 deadline = newExpiresAt == 0 ? uint64(block.timestamp + DEFAULT_LISTING_TTL) : newExpiresAt;
        item.price = newPrice;
        item.expiresAt = deadline;
        emit ListingUpdated(listingId, newPrice, deadline);
    }

    function cancelListing(uint256 listingId) external override whenNotPaused {
        Listing storage item = listings[listingId];
        if (item.seller != msg.sender) revert NotListingOwner();
        if (item.status != ListingStatus.Active) revert ListingNotActive();
        if (ListingMath.isStale(block.timestamp, item.expiresAt)) revert ListingPastExpiry();
        item.status = ListingStatus.Cancelled;
        emit ListingCancelled(listingId);
    }

    function cancelListings(uint256[] calldata listingIds) external override whenNotPaused {
        uint256 length = listingIds.length;
        if (length == 0 || length > MAX_BATCH_CANCEL) revert BatchTooLarge();
        for (uint256 i; i < length; ++i) {
            Listing storage item = listings[listingIds[i]];
            if (item.seller != msg.sender) revert NotListingOwner();
            if (item.status != ListingStatus.Active) revert ListingNotActive();
            if (ListingMath.isStale(block.timestamp, item.expiresAt)) revert ListingPastExpiry();
            item.status = ListingStatus.Cancelled;
            emit ListingCancelled(listingIds[i]);
        }
    }

    function expireListing(uint256 listingId) external override whenNotPaused {
        Listing storage item = listings[listingId];
        if (item.status != ListingStatus.Active) revert ListingNotActive();
        if (!ListingMath.isStale(block.timestamp, item.expiresAt)) revert ListingPastExpiry();
        item.status = ListingStatus.Expired;
        emit ListingExpired(listingId);
    }

    function buy(uint256 listingId) external payable override nonReentrant whenNotPaused {
        Listing storage item = listings[listingId];
        _requireActiveListing(item);
        if (msg.value != item.price) revert InsufficientValue();
        address seller = item.seller;
        if (msg.sender == seller) revert CannotBuyOwnListing();
        item.status = ListingStatus.Sold;
        uint16 feeBps = _effectiveFeeBps(seller);
        (uint256 fee, uint256 sellerAmount) = FeeMath.split(msg.value, feeBps);
        _creditTreasury(fee, keccak256("MARKETPLACE_FEE"));
        _creditTreasuryClaim(seller, sellerAmount, keccak256("MARKETPLACE_PROCEEDS"));
        ICustomNFT(item.nft).safeTransferFrom(seller, msg.sender, item.tokenId);
        emit ListingSold(listingId, msg.sender, item.price);
    }

    function makeOffer(address nft, uint256 tokenId, uint64 expiresAt)
        external
        payable
        override
        whenNotPaused
        returns (uint256 offerId)
    {
        if (nft == address(0)) revert ZeroAddress();
        if (nft.code.length == 0) revert UnsupportedAsset();
        if (msg.value == 0) revert InvalidPrice();
        if (expiresAt == 0 || expiresAt <= block.timestamp) revert InvalidExpiry();
        offerId = ++nextOfferId;
        offers[offerId] = Offer({
            id: offerId,
            buyer: msg.sender,
            nft: nft,
            tokenId: tokenId,
            amount: msg.value,
            expiresAt: expiresAt,
            status: OfferStatus.Active
        });
        buyerOffers[msg.sender].push(offerId);
        totalOfferEscrow += msg.value;
        emit OfferCreated(offerId, msg.sender, nft, tokenId, msg.value, expiresAt);
        _assertOfferEscrow();
    }

    function cancelOffer(uint256 offerId) external override nonReentrant whenNotPaused {
        Offer storage offer = offers[offerId];
        if (offer.buyer != msg.sender) revert NotOfferOwner();
        if (offer.status != OfferStatus.Active) revert OfferNotActive();
        _refundOffer(offer);
        offer.status = OfferStatus.Cancelled;
        emit OfferCancelled(offerId);
    }

    function expireOffer(uint256 offerId) external override nonReentrant whenNotPaused {
        Offer storage offer = offers[offerId];
        if (offer.status != OfferStatus.Active) revert OfferNotActive();
        if (offer.expiresAt > block.timestamp) revert OfferPastExpiry();
        _refundOffer(offer);
        offer.status = OfferStatus.Expired;
        emit OfferExpired(offerId);
    }

    function acceptOffer(uint256 offerId) external override nonReentrant whenNotPaused {
        Offer storage offer = offers[offerId];
        if (offer.status != OfferStatus.Active) revert OfferNotActive();
        if (offer.expiresAt <= block.timestamp) revert OfferPastExpiry();
        if (ICustomNFT(offer.nft).ownerOf(offer.tokenId) != msg.sender) revert NotListingOwner();
        offer.status = OfferStatus.Accepted;
        totalOfferEscrow -= offer.amount;
        uint16 feeBps = _effectiveFeeBps(msg.sender);
        (uint256 fee, uint256 sellerAmount) = FeeMath.split(offer.amount, feeBps);
        _creditTreasury(fee, keccak256("OFFER_FEE"));
        _creditTreasuryClaim(msg.sender, sellerAmount, keccak256("OFFER_PROCEEDS"));
        ICustomNFT(offer.nft).safeTransferFrom(msg.sender, offer.buyer, offer.tokenId);
        emit OfferAccepted(offerId, msg.sender, offer.amount);
        _assertOfferEscrow();
    }

    function rejectOffer(uint256 offerId) external override nonReentrant whenNotPaused {
        Offer storage offer = offers[offerId];
        if (offer.status != OfferStatus.Active) revert OfferNotActive();
        if (ICustomNFT(offer.nft).ownerOf(offer.tokenId) != msg.sender) revert NotListingOwner();
        _refundOffer(offer);
        offer.status = OfferStatus.Rejected;
        emit OfferRejected(offerId);
    }

    function automationDueOfferIds(uint256 cycle, uint256 maxScan, uint256 maxItems)
        external
        view
        returns (uint256[] memory dueIds)
    {
        if (maxItems == 0 || maxScan == 0 || paused()) return new uint256[](0);
        (uint256 startId, uint256 endId) = AutomationScanLib.window(nextOfferId, cycle, maxScan);
        uint256 capacity = AutomationScanLib.capacity(maxItems, startId, endId);
        dueIds = new uint256[](capacity);
        uint256 found;
        for (uint256 id = startId; id < endId && found < capacity; ++id) {
            Offer storage offer = offers[id];
            if (offer.status == OfferStatus.Active && offer.expiresAt != 0 && offer.expiresAt <= block.timestamp) {
                dueIds[found++] = id;
            }
        }
        assembly {
            mstore(dueIds, found)
        }
    }

    function hashListingOrder(
        address seller,
        address nft,
        uint256 tokenId,
        uint256 price,
        uint64 expiresAt,
        uint256 nonce
    ) external view override returns (bytes32) {
        return _listingOrderHash(seller, nft, tokenId, price, expiresAt, nonce);
    }

    function executeSignedListing(
        address seller,
        address nft,
        uint256 tokenId,
        uint256 price,
        uint64 expiresAt,
        uint256 nonce,
        bytes calldata signature
    ) external payable override nonReentrant whenNotPaused returns (bytes32 orderHash) {
        if (seller == address(0) || nft == address(0)) revert ZeroAddress();
        if (nft.code.length == 0) revert UnsupportedAsset();
        if (price == 0) revert InvalidPrice();
        if (seller == msg.sender) revert CannotBuyOwnListing();
        if (expiresAt <= block.timestamp) revert InvalidSignatureDeadline();
        if (nonce != orderNonce[seller]) revert InvalidNonce();
        orderHash = _listingOrderHash(seller, nft, tokenId, price, expiresAt, nonce);
        address recovered = ECDSA.recover(orderHash, signature);
        if (recovered != seller) revert SignatureInvalid();
        orderNonce[seller] = nonce + 1;
        _settleSignedListing(seller, nft, tokenId, price);
        emit SignedListingExecuted(orderHash, seller, msg.sender, nft, tokenId, price);
    }

    function setTreasury(address treasury_) external onlyRole(ADMIN_ROLE) {
        if (treasury_ == address(0)) revert ZeroAddress();
        if (treasury_.code.length == 0) revert UnsupportedAsset();
        if (!ITreasury(treasury_).authorizedPayer(address(this))) revert TreasuryNotAuthorized();
        treasury = treasury_;
        emit TreasuryUpdated(treasury_);
    }

    function setPaymentManager(address paymentManager_) external onlyRole(ADMIN_ROLE) {
        if (paymentManager_ == address(0)) revert ZeroAddress();
        if (paymentManager_.code.length == 0) revert UnsupportedAsset();
        if (!IPaymentManager(paymentManager_).authorizedCreditor(address(this))) revert PaymentManagerNotAuthorized();
        paymentManager = paymentManager_;
        emit PaymentManagerUpdated(paymentManager_);
    }

    function setProtocolFee(uint16 bps) external onlyRole(ADMIN_ROLE) {
        if (bps > 1000) revert InvalidBps();
        protocolFeeBps = bps;
        emit FeeConfigUpdated(protocolFeeBps, minimumFeeBps);
    }

    function setMinimumFeeBps(uint16 bps) external onlyRole(ADMIN_ROLE) {
        if (bps > 1000) revert InvalidBps();
        minimumFeeBps = bps;
        emit FeeConfigUpdated(protocolFeeBps, minimumFeeBps);
    }

    function setCustomFee(address account, uint16 bps, bool active) external onlyRole(ADMIN_ROLE) {
        if (account == address(0)) revert ZeroAddress();
        if (bps > 1000) revert InvalidBps();
        customFeeBps[account] = bps;
        customFeeEnabled[account] = active;
        emit CustomFeeUpdated(account, bps, active);
    }

    function invalidateNonce() external override {
        uint256 newNonce = orderNonce[msg.sender] + 1;
        orderNonce[msg.sender] = newNonce;
        emit OrderNonceInvalidated(msg.sender, newNonce);
    }

    function pause() external onlyRole(OPERATOR_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(OPERATOR_ROLE) {
        _unpause();
    }

    function getListing(uint256 listingId) external view override returns (Listing memory) {
        return listings[listingId];
    }

    function getOffer(uint256 offerId) external view override returns (Offer memory) {
        return offers[offerId];
    }

    function sellerListingCount(address seller) external view returns (uint256) {
        return sellerListings[seller].length;
    }

    function sellerListingAt(address seller, uint256 index) external view returns (uint256) {
        return sellerListings[seller][index];
    }

    function buyerOfferCount(address buyer) external view returns (uint256) {
        return buyerOffers[buyer].length;
    }

    function buyerOfferAt(address buyer, uint256 index) external view returns (uint256) {
        return buyerOffers[buyer][index];
    }

    function listingCount() external view returns (uint256) {
        return nextListingId;
    }

    function nonceOf(address account) external view override returns (uint256) {
        return orderNonce[account];
    }

    function offerCount() external view returns (uint256) {
        return nextOfferId;
    }

    function domainInfo() external pure returns (string memory name_, string memory version_) {
        return ("Professional Marketplace", "1");
    }

    function version() external pure returns (uint64) {
        return 2;
    }

    function _createListing(address seller, address nft, uint256 tokenId, uint256 price, uint64 expiresAt)
        internal
        returns (uint256 listingId)
    {
        if (nft == address(0)) revert ZeroAddress();
        if (nft.code.length == 0) revert UnsupportedAsset();
        if (price == 0) revert InvalidPrice();
        if (expiresAt != 0 && expiresAt <= block.timestamp) revert InvalidExpiry();
        if (ICustomNFT(nft).ownerOf(tokenId) != seller) revert NotListingOwner();
        if (expiresAt == 0 && block.timestamp > type(uint64).max - DEFAULT_LISTING_TTL) revert InvalidExpiry();
        listingId = ++nextListingId;
        uint64 deadline = expiresAt == 0 ? uint64(block.timestamp + DEFAULT_LISTING_TTL) : expiresAt;
        listings[listingId] = Listing({
            id: listingId,
            seller: seller,
            nft: nft,
            tokenId: tokenId,
            price: price,
            expiresAt: deadline,
            status: ListingStatus.Active
        });
        sellerListings[seller].push(listingId);
        emit ListingCreated(listingId, seller, nft, tokenId, price, deadline);
    }

    function _settleSignedListing(address seller, address nft, uint256 tokenId, uint256 price) internal {
        if (msg.value != price) revert InsufficientValue();
        if (ICustomNFT(nft).ownerOf(tokenId) != seller) revert SellerNoLongerOwnsAsset();
        uint16 feeBps = _effectiveFeeBps(seller);
        (uint256 fee, uint256 sellerAmount) = FeeMath.split(msg.value, feeBps);
        _creditTreasury(fee, keccak256("SIGNED_LISTING_FEE"));
        _creditTreasuryClaim(seller, sellerAmount, keccak256("SIGNED_LISTING_PROCEEDS"));
        ICustomNFT(nft).safeTransferFrom(seller, msg.sender, tokenId);
    }

    function _listingOrderHash(
        address seller,
        address nft,
        uint256 tokenId,
        uint256 price,
        uint64 expiresAt,
        uint256 nonce
    ) internal view returns (bytes32) {
        bytes32 structHash = OrderHashLib.hashStruct(seller, nft, tokenId, price, expiresAt, nonce);
        return _hashTypedDataV4(structHash);
    }

    function _effectiveFeeBps(address seller) internal view returns (uint16) {
        if (customFeeEnabled[seller]) return customFeeBps[seller];
        return protocolFeeBps < minimumFeeBps ? minimumFeeBps : protocolFeeBps;
    }

    function _requireActiveListing(Listing storage item) internal view {
        if (item.seller == address(0) || item.status != ListingStatus.Active) revert ListingNotActive();
        if (!ListingMath.activeAt(block.timestamp, item.expiresAt)) revert ListingPastExpiry();
        if (ICustomNFT(item.nft).ownerOf(item.tokenId) != item.seller) revert SellerNoLongerOwnsAsset();
    }

    function _refundOffer(Offer storage offer) internal {
        uint256 amount = offer.amount;
        totalOfferEscrow -= amount;
        IPaymentManager(paymentManager).credit{ value: amount }(offer.buyer, keccak256("OFFER_REFUND"));
        _assertOfferEscrow();
    }

    function _creditTreasury(uint256 amount, bytes32 reason) internal {
        if (amount == 0) return;
        ITreasury(treasury).credit{ value: amount }(ITreasury(treasury).feeRecipientForProtocol(), reason);
    }

    function _creditTreasuryClaim(address account, uint256 amount, bytes32 reason) internal {
        if (amount == 0) return;
        ITreasury(treasury).credit{ value: amount }(account, reason);
    }

    function _assertOfferEscrow() internal view {
        if (address(this).balance < totalOfferEscrow) revert EscrowInvariantBroken();
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE) { }
}

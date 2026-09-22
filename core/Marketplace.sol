// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";


import "../interfaces/IMarketplace.sol";
import "../interfaces/ICustomNFT.sol";
import "../interfaces/ITreasury.sol";
import "../interfaces/IPaymentManager.sol";
import "../proxy/interfaces/IUpgradeableSystem.sol";
import "../libraries/FeeMath.sol";
import "../libraries/ListingMath.sol";
import "../libraries/OrderHashLib.sol";

contract Marketplace is Initializable, UUPSUpgradeable, AccessControlUpgradeable, PausableUpgradeable, ReentrancyGuard, EIP712Upgradeable, IMarketplace, IUpgradeableSystem {
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    uint64 public constant DEFAULT_LISTING_TTL = 7 days;
    uint256 public constant MAX_BATCH_CANCEL = 50;
    bytes32 public constant LISTING_TYPEHASH = keccak256("ListingOrder(address seller,address nft,uint256 tokenId,uint256 price,uint64 expiresAt,uint256 nonce)");
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
    mapping(bytes32 => bool) public usedOrderHashes;

    event FeeTierUpdated(address indexed account, uint16 feeBps);

    constructor() {
        _disableInitializers();
    }

    function initialize(address admin,address treasury_,address paymentManager_) public override initializer {
        if (admin == address(0) ||treasury_ == address(0) ||paymentManager_ == address(0)) revert ZeroAddress();
        __AccessControl_init();
        __Pausable_init();
        __EIP712_init("Professional Marketplace", "1");
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ADMIN_ROLE, admin);
        _grantRole(OPERATOR_ROLE, admin);
        treasury = treasury_;
        paymentManager = paymentManager_;
        protocolFeeBps = 250;
        minimumFeeBps = 100;
    }

    // listing
    function createListing(address nft,uint256 tokenId,uint256 price,uint64 expiresAt) external override whenNotPaused returns (uint256 listingId) {
        listingId = _createListing(msg.sender,nft,tokenId,price,expiresAt);
    }

    function updateListing(uint256 listingId,uint256 newPrice,uint64 newExpiresAt) external override whenNotPaused {
        Listing storage item = listings[listingId];
        if (item.seller != msg.sender) revert NotListingOwner();
        if (item.status != ListingStatus.Active) revert ListingNotActive();
        if (newPrice == 0) revert InvalidPrice();
        if (newExpiresAt != 0 && newExpiresAt <= block.timestamp) revert InvalidExpiry();
        if (ICustomNFT(item.nft).ownerOf(item.tokenId) !=item.seller) {revert SellerNoLongerOwnsAsset();}
        item.price = newPrice;
        item.expiresAt = newExpiresAt;
        emit ListingUpdated(listingId,newPrice,newExpiresAt);
    }

    function cancelListing(uint256 listingId) external override whenNotPaused {
        Listing storage item = listings[listingId];
        if (item.seller != msg.sender) revert NotListingOwner();
        if (item.status != ListingStatus.Active) revert ListingNotActive();
        item.status = ListingStatus.Cancelled;
        emit ListingCancelled(listingId);
    }

    function cancelListings(uint256[] calldata listingIds) external override whenNotPaused{
        uint256 length = listingIds.length;
        if (length == 0 || length > MAX_BATCH_CANCEL) revert BatchTooLarge();
        for (uint256 i = 0; i < length; i++) {
            Listing storage item = listings[listingIds[i]];
            if (item.seller != msg.sender) revert NotListingOwner();
            if (item.status != ListingStatus.Active) revert ListingNotActive();
            item.status = ListingStatus.Cancelled;
            emit ListingCancelled(listingIds[i]);
        }
    }

    function expireListing(uint256 listingId) external override whenNotPaused {
        Listing storage item = listings[listingId];
        if (item.status != ListingStatus.Active) revert ListingNotActive();
        if (!ListingMath.isStale(uint64(block.timestamp),item.expiresAt)) revert ListingPastExpiry();
        item.status = ListingStatus.Expired;
        emit ListingExpired(listingId);
    }

    // buy
    function buy(uint256 listingId) external payable override nonReentrant whenNotPaused {
        Listing storage item = listings[listingId];
        _requireActiveListing(item);
        if (msg.value != item.price) revert InsufficientValue();
        address seller = item.seller;
        item.status = ListingStatus.Sold;
        uint16 feeBps =_effectiveFeeBps(seller);
        (uint256 fee, uint256 sellerAmount) = FeeMath.split(msg.value, feeBps);
        _creditTreasury(fee,keccak256("MARKETPLACE_FEE"));
        _creditTreasuryClaim(seller,sellerAmount,keccak256("MARKETPLACE_PROCEEDS"));
        ICustomNFT(item.nft).safeTransferFrom(seller,msg.sender,item.tokenId);
        _assertOfferEscrow();
        emit ListingSold(listingId,msg.sender,item.price);
    }

    // offer
    function makeOffer(address nft,uint256 tokenId,uint64 expiresAt) external payable override whenNotPaused returns (uint256 offerId) {
        if (nft == address(0)) revert ZeroAddress();
        if (msg.value == 0) revert InvalidPrice();
        if (expiresAt == 0 ||expiresAt <= block.timestamp) revert InvalidExpiry();
        offerId = ++nextOfferId;
        offers[offerId] = Offer({id: offerId,buyer: msg.sender,nft: nft,tokenId: tokenId,amount: msg.value,expiresAt: expiresAt,status: OfferStatus.Active});
        buyerOffers[msg.sender].push(offerId);
        totalOfferEscrow += msg.value;
        emit OfferCreated(offerId,msg.sender,nft,tokenId,msg.value,expiresAt);
        _assertOfferEscrow();
    }

    function cancelOffer(uint256 offerId) external override nonReentrant whenNotPaused {
        Offer storage offer = offers[offerId];
        if (offer.buyer != msg.sender) revert NotOfferOwner();
        if (offer.status != OfferStatus.Active)revert OfferNotActive();
        offer.status = OfferStatus.Cancelled;
        totalOfferEscrow -= offer.amount;
        IPaymentManager(paymentManager).credit{value: offer.amount}(offer.buyer,keccak256("OFFER_CANCELLED"));
        emit OfferCancelled(offerId);
        _assertOfferEscrow();
    }

    function expireOffer(uint256 offerId) external override nonReentrant whenNotPaused {
        Offer storage offer = offers[offerId];
        if (offer.status != OfferStatus.Active) { revert OfferNotActive(); }
        if (offer.expiresAt > block.timestamp) { revert OfferPastExpiry(); }
        offer.status = OfferStatus.Expired;
        totalOfferEscrow -= offer.amount;
        IPaymentManager(paymentManager).credit{value: offer.amount}(offer.buyer,keccak256(""));
        emit OfferExpired(offerId);
        _assertOfferEscrow();
    }

    function acceptOffer(uint256 offerId) external override nonReentrant whenNotPaused {
        Offer storage offer = offers[offerId];
        if (offer.status != OfferStatus.Active) { revert OfferNotActive(); }
        if (offer.expiresAt <= block.timestamp) { revert OfferPastExpiry(); }
        if (ICustomNFT(offer.nft).ownerOf(offer.tokenId) != msg.sender) { revert NotListingOwner(); }
        offer.status = OfferStatus.Accepted;
        totalOfferEscrow -= offer.amount;
        uint16 feeBps = _effectiveFeeBps(msg.sender);
        (uint256 fee, uint256 sellerAmount) = FeeMath.split(offer.amount, feeBps);
        _creditTreasury(fee,keccak256("OFFER_FEE"));
        _creditTreasuryClaim(msg.sender,sellerAmount,keccak256("OFFER_PROCEEDS"));
        ICustomNFT(offer.nft).safeTransferFrom(msg.sender,offer.buyer,offer.tokenId);
        emit OfferAccepted(offerId,msg.sender,offer.amount);
        _assertOfferEscrow();
    }

    function rejectOffer(uint256 offerId) external override nonReentrant whenNotPaused {
        Offer storage offer = offers[offerId];
        if (ICustomNFT(offer.nft).ownerOf(offer.tokenId) != msg.sender) { revert NotListingOwner(); }
        if (offer.status != OfferStatus.Active) { revert OfferNotActive(); }
        offer.status = OfferStatus.Rejected;
        totalOfferEscrow -= offer.amount;
        IPaymentManager(paymentManager).credit{value: offer.amount}(offer.buyer,keccak256("OFFER_REJECTED"));
        emit OfferRejected(offerId);
        _assertOfferEscrow();
    }

    /* ============================================================= */
    /*                      SIGNED LISTINGS                          */
    /* ============================================================= */

    function hashListingOrder(address seller,address nft,uint256 tokenId,uint256 price,uint64 expiresAt,uint256 nonce) external view override returns (bytes32) {
        return _listingOrderHash(seller,nft,tokenId,price,expiresAt,nonce);
    }

    function executeSignedListing(address seller,address nft,uint256 tokenId,uint256 price,uint64 expiresAt,uint256 nonce,bytes calldata signature) external payable override nonReentrant whenNotPaused returns (bytes32 orderHash) {
        if (seller == address(0) || nft == address(0)) { revert ZeroAddress(); }
        if (price == 0) { revert InvalidPrice(); }
        if (expiresAt <= block.timestamp) { revert InvalidSignatureDeadline(); }
        if (nonce != orderNonce[seller]) { revert InvalidNonce(); }
        orderHash = _listingOrderHash(seller,nft,tokenId,price,expiresAt,nonce);
        if (usedOrderHashes[orderHash]) { revert OrderAlreadyUsed(); }
        address recovered = ECDSA.recover(orderHash,signature);
        if (recovered != seller) { revert SignatureInvalid(); }
        usedOrderHashes[orderHash] = true;
        orderNonce[seller] = nonce + 1;
        _settleSignedListing(seller,nft,tokenId,price);
        emit SignedListingExecuted(orderHash,seller,msg.sender,nft,tokenId,price);
    }

    /* ============================================================= */
    /*                         CONFIG                                */
    /* ============================================================= */

    function setTreasury(address treasury_) external onlyRole(ADMIN_ROLE) {
        if (treasury_ == address(0)) { revert ZeroAddress(); }
        treasury = treasury_;
        emit TreasuryUpdated(treasury_);
    }

    function setPaymentManager(address paymentManager_) external onlyRole(ADMIN_ROLE) {
        if (paymentManager_ == address(0)) { revert ZeroAddress(); }
        paymentManager = paymentManager_;
        emit PaymentManagerUpdated(paymentManager_);
    }

    function setProtocolFee(uint16 bps) external onlyRole(ADMIN_ROLE) {
        if (bps > 1000) { revert InvalidBps(); }
        protocolFeeBps = bps;
    }

    function setMinimumFeeBps(uint16 bps) external onlyRole(ADMIN_ROLE) {
        if (bps > 1000) revert InvalidBps();
        minimumFeeBps = bps;
    }

    function customFeeManage(address account,uint16 bps , bool active) external onlyRole(ADMIN_ROLE) {
        if (bps > 1000) { revert InvalidBps(); }
        customFeeBps[account] = bps;
        customFeeEnabled[account] = active;
        emit FeeTierUpdated(account, bps);
    }


    function invalidateNonce() external override {
        orderNonce[msg.sender] += 1;
    }

    function pause() external onlyRole(OPERATOR_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(OPERATOR_ROLE) {
        _unpause();
    }

    /* ============================================================= */
    /*                           VIEWS                               */
    /* ============================================================= */

    function getListing(uint256 listingId) external view override returns (Listing memory) {
        return listings[listingId];
    }

    function getOffer(uint256 offerId) external view override returns (Offer memory) {
        return offers[offerId];
    }

    function sellerListingCount(address seller) external view returns (uint256) {
        return sellerListings[seller].length;
    }

    function sellerListingAt(address seller,uint256 index) external view returns (uint256) {
        return sellerListings[seller][index];
    }

    function buyerOfferCount(address buyer) external view returns (uint256) {
        return buyerOffers[buyer].length;
    }

    function buyerOfferAt(address buyer,uint256 index) external view returns (uint256) {
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

    function domainInfo() external pure returns (string memory name_,string memory version_) {
        return ("Professional Marketplace","1");
    }

    function version() external pure override returns (uint64) {
        return 2;
    }

    /* ============================================================= */
    /*                       INTERNAL ALGORITHMS                     */
    /* ============================================================= */

    function _createListing(address seller,address nft,uint256 tokenId,uint256 price,uint64 expiresAt) internal returns (uint256 listingId) {
        if (nft == address(0)) { revert ZeroAddress(); }
        if (price == 0) { revert InvalidPrice(); }
        if (expiresAt != 0 && expiresAt <= block.timestamp) { revert InvalidExpiry(); }
        if (ICustomNFT(nft).ownerOf(tokenId) != seller) { revert NotListingOwner(); }
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
        emit ListingCreated(listingId,seller,nft,tokenId,price,deadline);
    }

    function _settleSignedListing(address seller,address nft,uint256 tokenId,uint256 price) internal {
        if (msg.value != price) { revert InsufficientValue(); }
        if (ICustomNFT(nft).ownerOf(tokenId) != seller) { revert SellerNoLongerOwnsAsset(); }
        uint16 feeBps = _effectiveFeeBps(seller);
        (uint256 fee, uint256 sellerAmount) = FeeMath.split(msg.value, feeBps);
        _creditTreasury(fee,keccak256("SIGNED_LISTING_FEE"));
        _creditTreasuryClaim(seller,sellerAmount,keccak256("SIGNED_LISTING_PROCEEDS"));
        ICustomNFT(nft).safeTransferFrom(seller,msg.sender,tokenId);
    }

    function _listingOrderHash(address seller,address nft,uint256 tokenId,uint256 price,uint64 expiresAt,uint256 nonce) internal view returns (bytes32) {
        bytes32 structHash = OrderHashLib.hashStruct(seller,nft,tokenId,price,expiresAt,nonce);
        return _hashTypedDataV4(structHash);
    }

    function _effectiveFeeBps(address seller) internal view returns (uint16) {
        if (customFeeEnabled[seller]) { return customFeeBps[seller]; }
        return protocolFeeBps < minimumFeeBps ? minimumFeeBps : protocolFeeBps;
    }

    function _requireActiveListing(Listing storage item) internal view {
        if (item.seller == address(0) || item.status != ListingStatus.Active) { revert ListingNotActive(); }
        if (!ListingMath.activeAt(uint64(block.timestamp),item.expiresAt)) { revert ListingPastExpiry(); }
        if (ICustomNFT(item.nft).ownerOf(item.tokenId) != item.seller) { revert SellerNoLongerOwnsAsset(); }
    }

    function _creditTreasury(uint256 amount,bytes32 reason) internal {
        if (amount == 0) { return; }
        ITreasury(treasury).credit{value: amount}(ITreasury(treasury).feeRecipientForProtocol(),reason);
    }

    function _creditTreasuryClaim(address account,uint256 amount,bytes32 reason) internal {
        if (amount == 0) { return; }
        ITreasury(treasury).credit{value: amount}(account,reason);
    }

    function _assertOfferEscrow() internal view {
        if (address(this).balance < totalOfferEscrow) { revert EscrowInvariantBroken(); }
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE) {
        emit UpgradeAuthorized(newImplementation,msg.sender);
        emit UpgradedByProtocol(newImplementation,msg.sender);
    }
}

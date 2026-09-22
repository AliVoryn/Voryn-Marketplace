pragma solidity ^0.8.24;
import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../core/Marketplace.sol";
import "../core/CustomNFT.sol";
import "../core/OpenAuction.sol";
import "../core/Staking.sol";
import "../core/Treasury.sol";
import "../core/PaymentManager.sol";
import "../core/BlindAuction.sol";
import "../core/DutchAuction.sol";
import "../core/Raffle.sol";
import "../registries/ProtocolRegistry.sol";
import "../interfaces/IFactory.sol";
import "../interfaces/ITreasury.sol";
import "../interfaces/ICustomNFT.sol";
contract ProtocolFactory is Ownable2Step, IFactory {
    bytes32 public constant KIND_MARKETPLACE = keccak256("MARKETPLACE");
    bytes32 public constant KIND_NFT = keccak256("NFT");
    bytes32 public constant KIND_AUCTION = keccak256("AUCTION");
    bytes32 public constant KIND_OPEN_AUCTION = keccak256("OPEN_AUCTION");
    bytes32 public constant KIND_BLIND_AUCTION = keccak256("BLIND_AUCTION");
    bytes32 public constant KIND_DUTCH_AUCTION = keccak256("DUTCH_AUCTION");
    bytes32 public constant KIND_STAKING = keccak256("STAKING");
    bytes32 public constant KIND_RAFFLE = keccak256("RAFFLE");
    bytes32 public constant KIND_TREASURY = keccak256("TREASURY");
    bytes32 public constant KIND_PAYMENT_MANAGER = keccak256("PAYMENT_MANAGER");
    ProtocolRegistry public immutable registry;
    Marketplace public immutable marketplaceImplementation;
    mapping(address => address[]) private instancesByCreator;
    mapping(address => mapping(bytes32 => bool)) public usedSalts;

    struct SuiteDeployment {
        address treasury;
        address paymentManager;
        address marketplace;
        address auction;
        address dutchAuction;
        address staking;
    }
    error ZeroAddress();
    error SaltAlreadyUsed();
    error UnauthorizedTreasuryOwner();
    error UnauthorizedPaymentManagerOwner();  
    error NotSeller();  
    event RegistryReferenceSet(address indexed registryAddress);
    event ProtocolSuiteCreated(
        address indexed creator,
        address treasury,
        address paymentManager,
        address marketplace,
        address auction,
        address staking
    );
    event ProtocolSuiteDutchAuctionCreated(address indexed creator, address treasury, address dutchAuction);
    constructor(address initialOwner) Ownable(initialOwner) {
        registry = new ProtocolRegistry(address(this));
        marketplaceImplementation = new Marketplace();
        emit RegistryReferenceSet(address(registry));
    }
    function createTreasury(address feeRecipient) external override returns (address instance) {
        if (feeRecipient == address(0)) revert ZeroAddress();
        Treasury treasury = new Treasury(address(this), feeRecipient);
        instance = address(treasury);
        treasury.transferOwnership(msg.sender);
        _register(instance, msg.sender, address(0), KIND_TREASURY);
        emit InstanceCreated(instance, msg.sender, KIND_TREASURY, address(0));
    }
    function createPaymentManager() external override returns (address instance) {
        PaymentManager manager = new PaymentManager(address(this));
        instance = address(manager);
        manager.transferOwnership(msg.sender);
        _register(instance, msg.sender, address(0), KIND_PAYMENT_MANAGER);
        emit InstanceCreated(instance, msg.sender, KIND_PAYMENT_MANAGER, address(0));
    }
    function createMarketplace(address admin, address treasury_, address paymentManager_)
        external
        override
        returns (address instance)
    {
        if (admin == address(0) || treasury_ == address(0) || paymentManager_ == address(0)) revert ZeroAddress();
        if (Ownable(treasury_).owner() != address(this)) revert UnauthorizedTreasuryOwner();
        if (Ownable(paymentManager_).owner() != address(this)) revert UnauthorizedPaymentManagerOwner();
        bytes memory data = abi.encodeCall(Marketplace.initialize, (admin, treasury_, paymentManager_));
        ERC1967Proxy proxy = new ERC1967Proxy(address(marketplaceImplementation), data);
        instance = address(proxy);
        ITreasury(treasury_).setAuthorizedPayer(instance, true);
        PaymentManager(payable(paymentManager_)).setCreditor(instance, true);
        _register(instance, msg.sender, address(marketplaceImplementation), KIND_MARKETPLACE);
        emit InstanceCreated(instance, msg.sender, KIND_MARKETPLACE, address(marketplaceImplementation));
    }
    function createCustomNFT(string calldata name_, string calldata symbol_, uint maxSupply_, address admin)
        external
        override
        returns (address instance)
    {
        if (admin == address(0)) revert ZeroAddress();
        CustomNFT nft = new CustomNFT(name_, symbol_, maxSupply_, admin);
        instance = address(nft);
        _register(instance, msg.sender, address(0), KIND_NFT);
        emit InstanceCreated(instance, msg.sender, KIND_NFT, address(0));
    }
    function createCustomNFTDeterministic(
        string calldata name_,
        string calldata symbol_,
        uint maxSupply_,
        address admin,
        bytes32 salt
    ) external override returns (address instance) {
        if (admin == address(0)) revert ZeroAddress();
        if (usedSalts[msg.sender][salt]) revert SaltAlreadyUsed();
        usedSalts[msg.sender][salt] = true;
        bytes32 namespacedSalt = keccak256(abi.encode(msg.sender, salt));
        CustomNFT nft = new CustomNFT{salt: namespacedSalt}(name_, symbol_, maxSupply_, admin);
        instance = address(nft);
        _register(instance, msg.sender, address(0), KIND_NFT);
        emit DeterministicNFTCreated(instance, msg.sender, salt);
        emit InstanceCreated(instance, msg.sender, KIND_NFT, address(0));
    }
    function predictCustomNFTAddress(
        address creator,
        string calldata name_,
        string calldata symbol_,
        uint maxSupply_,
        address admin,
        bytes32 salt
    ) external view override returns (address) {
        bytes32 namespacedSalt = keccak256(abi.encode(creator, salt));
        bytes32 initCodeHash = keccak256(
            abi.encodePacked(type(CustomNFT).creationCode, abi.encode(name_, symbol_, maxSupply_, admin))
        );
        return address(uint160(uint(keccak256(abi.encodePacked(bytes1(0xff), address(this), namespacedSalt, initCodeHash)))));
    }
    function createAuctionInstance(address treasury_) external override returns (address instance) {
        if (treasury_ == address(0)) revert ZeroAddress();
        if (Ownable(treasury_).owner() != address(this)) revert UnauthorizedTreasuryOwner();
        OpenAuction auction = new OpenAuction(msg.sender, treasury_, 250);
        instance = address(auction);
        ITreasury(treasury_).setAuthorizedPayer(address(auction), true);
        _register(instance, msg.sender, address(0), KIND_AUCTION);
        emit InstanceCreated(instance, msg.sender, KIND_AUCTION, address(0));
    }
    function createBlindAuctionInstance(
        address owner,
        address payable beneficiary,
        address nft,
        uint256 tokenId,
        address treasury_,
        uint16 feeBps,
        uint256 biddingTime,
        uint256 revealTime,
        uint256 reservePrice
    ) external override returns (address instance) {
        if (owner == address(0) || beneficiary == address(0)) revert ZeroAddress();
        if (nft == address(0) || treasury_ == address(0)) revert ZeroAddress();
        if (msg.sender != beneficiary) revert NotSeller();
        if (Ownable(treasury_).owner() != address(this)) revert UnauthorizedTreasuryOwner();
        if (ICustomNFT(nft).ownerOf(tokenId) != beneficiary) revert NotSeller();
        ICustomNFT(nft).transferFrom(beneficiary, address(this), tokenId);
        BlindAuction auction =
            new BlindAuction(owner, beneficiary, nft, tokenId, treasury_, feeBps, biddingTime, revealTime, reservePrice);
        instance = address(auction);
        ICustomNFT(nft).transferFrom(address(this), instance, tokenId);
        ITreasury(treasury_).setAuthorizedPayer(instance, true);
        _register(instance, owner, address(0), KIND_BLIND_AUCTION);
        emit InstanceCreated(instance, owner, KIND_BLIND_AUCTION, address(0));
    }
    function createDutchAuctionInstance(address owner, address treasury_, uint16 feeBps)
        external
        override
        returns (address instance)
    {
        if (owner == address(0) || treasury_ == address(0)) revert ZeroAddress();
        if (Ownable(treasury_).owner() != address(this)) revert UnauthorizedTreasuryOwner();
        DutchAuction auction = new DutchAuction(owner, treasury_, feeBps);
        instance = address(auction);
        ITreasury(treasury_).setAuthorizedPayer(address(auction), true);
        _register(instance, owner, address(0), KIND_DUTCH_AUCTION);
        emit InstanceCreated(instance, owner, KIND_DUTCH_AUCTION, address(0));
    }
    function createStaking(address rewardTreasury) external override returns (address instance) {
        if (rewardTreasury == address(0)) revert ZeroAddress();
        if (Ownable(rewardTreasury).owner() != address(this)) revert UnauthorizedTreasuryOwner();
        Staking staking = new Staking(msg.sender, rewardTreasury);
        instance = address(staking);
        ITreasury(rewardTreasury).setAuthorizedPayer(instance, true);
        _register(instance, msg.sender, address(0), KIND_STAKING);
        emit InstanceCreated(instance, msg.sender, KIND_STAKING, address(0));
    }
    function createRaffleInstance(
        address owner,
        address treasury_,
        uint16 feeBps,
        address vrfCoordinator,
        uint256 subscriptionId,
        bytes32 keyHash,
        uint32 callbackGasLimit,
        uint16 requestConfirmations,
        bool nativePayment
    ) external override returns (address instance) {
        if (owner == address(0) || treasury_ == address(0)) revert ZeroAddress();
        if (Ownable(treasury_).owner() != address(this)) revert UnauthorizedTreasuryOwner();
        Raffle raffle = new Raffle(
            owner,
            treasury_,
            feeBps,
            vrfCoordinator,
            subscriptionId,
            keyHash,
            callbackGasLimit,
            requestConfirmations,
            nativePayment
        );
        instance = address(raffle);
        ITreasury(treasury_).setAuthorizedPayer(instance, true);
        _register(instance, owner, address(0), KIND_RAFFLE);
        emit InstanceCreated(instance, owner, KIND_RAFFLE, address(0));
    }
    function creatorInstanceCount(address creator) external view override returns (uint) {
        return instancesByCreator[creator].length;
    }
    function creatorInstanceAt(address creator, uint index) external view override returns (address) {
        return instancesByCreator[creator][index];
    }
    function createProtocolSuite(address admin, address feeRecipient)
        external
        override
        returns (address, address, address, address, address, address)
    {
        if (admin == address(0) || feeRecipient == address(0)) revert ZeroAddress();
        SuiteDeployment memory suite;
        suite.treasury = address(new Treasury(address(this), feeRecipient));
        suite.paymentManager = address(new PaymentManager(address(this)));
        bytes memory initData = abi.encodeCall(Marketplace.initialize, (admin, suite.treasury, suite.paymentManager));
        suite.marketplace = address(new ERC1967Proxy(address(marketplaceImplementation), initData));
        suite.auction = address(new OpenAuction(admin, suite.treasury, 250));
        suite.dutchAuction = address(new DutchAuction(admin, suite.treasury, 250));
        suite.staking = address(new Staking(admin, suite.treasury));
        Treasury(payable(suite.treasury)).setAuthorizedPayer(suite.marketplace, true);
        Treasury(payable(suite.treasury)).setAuthorizedPayer(suite.auction, true);
        Treasury(payable(suite.treasury)).setAuthorizedPayer(suite.dutchAuction, true);
        Treasury(payable(suite.treasury)).setAuthorizedPayer(suite.staking, true);
        PaymentManager(payable(suite.paymentManager)).setCreditor(suite.marketplace, true);
        Treasury(payable(suite.treasury)).transferOwnership(admin);
        PaymentManager(payable(suite.paymentManager)).transferOwnership(admin);
        _register(suite.treasury, msg.sender, address(0), KIND_TREASURY);
        _register(suite.paymentManager, msg.sender, address(0), KIND_PAYMENT_MANAGER);
        _register(suite.marketplace, msg.sender, address(marketplaceImplementation), KIND_MARKETPLACE);
        _register(suite.auction, msg.sender, address(0), KIND_AUCTION);
        _register(suite.dutchAuction, msg.sender, address(0), KIND_DUTCH_AUCTION);
        _register(suite.staking, msg.sender, address(0), KIND_STAKING);
        emit ProtocolSuiteCreated(msg.sender, suite.treasury, suite.paymentManager, suite.marketplace, suite.auction, suite.staking);
        emit ProtocolSuiteDutchAuctionCreated(msg.sender, suite.treasury, suite.dutchAuction);
        return (suite.treasury, suite.paymentManager, suite.marketplace, suite.auction, suite.staking, suite.dutchAuction);
    }
    function transferRegistryOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ZeroAddress();
        registry.setRegistrar(address(this), true);
        registry.transferOwnership(newOwner);
    }
    function _register(address instance, address creator, address implementation, bytes32 kind) internal {
        instancesByCreator[creator].push(instance);
        registry.registerInstance(instance, creator, implementation, kind, 1);
    }
}

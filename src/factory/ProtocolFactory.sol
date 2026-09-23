// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
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
import "../interfaces/IPaymentManager.sol";
import "../interfaces/ICustomNFT.sol";
import "./deployers/CoreDeployer.sol";
import "./deployers/NFTDeployer.sol";
import "./deployers/AuctionDeployer.sol";
import "./deployers/BlindAuctionDeployer.sol";
import "./deployers/StakingDeployer.sol";
import "./deployers/RaffleDeployer.sol";

contract ProtocolFactory is Ownable2Step, ReentrancyGuard, IFactory {
    bytes32 public constant KIND_MARKETPLACE = keccak256("MARKETPLACE");
    bytes32 public constant KIND_NFT = keccak256("NFT");
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
    error UnauthorizedTreasuryController();
    error UnauthorizedPaymentManagerController();
    error NotSeller();
    error InvalidContract();
    error NotTreasuryAuthority();
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
    event ProtocolSuiteControllersFinalized(address indexed treasury, address indexed paymentManager);

    constructor(address initialOwner) Ownable(initialOwner) {
        registry = new ProtocolRegistry(address(this));
        marketplaceImplementation = new Marketplace();
        emit RegistryReferenceSet(address(registry));
    }

    function createTreasury(address feeRecipient) external override returns (address instance) {
        if (feeRecipient == address(0)) revert ZeroAddress();
        instance = CoreDeployer.deployTreasury(address(this), feeRecipient, address(this));
        Ownable2Step(instance).transferOwnership(msg.sender);
        _register(instance, msg.sender, address(0), KIND_TREASURY);
        emit InstanceCreated(instance, msg.sender, KIND_TREASURY, address(0));
    }

    function createPaymentManager() external override returns (address instance) {
        instance = CoreDeployer.deployPaymentManager(address(this), address(this));
        Ownable2Step(instance).transferOwnership(msg.sender);
        _register(instance, msg.sender, address(0), KIND_PAYMENT_MANAGER);
        emit InstanceCreated(instance, msg.sender, KIND_PAYMENT_MANAGER, address(0));
    }

    function createMarketplace(address admin, address treasury_, address paymentManager_)
        external
        override
        nonReentrant
        returns (address instance)
    {
        if (admin == address(0) || treasury_ == address(0) || paymentManager_ == address(0)) {
            revert ZeroAddress();
        }
        if (treasury_.code.length == 0 || paymentManager_.code.length == 0) revert InvalidContract();
        if (ITreasury(treasury_).factoryController() != address(this)) revert UnauthorizedTreasuryController();
        if (IPaymentManager(paymentManager_).factoryController() != address(this)) {
            revert UnauthorizedPaymentManagerController();
        }
        _requireTreasuryAuthority(treasury_);
        bytes memory data = abi.encodeCall(Marketplace.initialize, (admin, treasury_, paymentManager_));
        instance = CoreDeployer.deployProxy(address(marketplaceImplementation), data);
        ITreasury(treasury_).setAuthorizedPayer(instance, true);
        PaymentManager(payable(paymentManager_)).setCreditor(instance, true);
        _register(instance, msg.sender, address(marketplaceImplementation), KIND_MARKETPLACE);
        emit InstanceCreated(instance, msg.sender, KIND_MARKETPLACE, address(marketplaceImplementation));
    }

    function createCustomNFT(string calldata name_, string calldata symbol_, uint256 maxSupply_, address admin)
        external
        override
        returns (address instance)
    {
        if (admin == address(0)) revert ZeroAddress();
        instance = NFTDeployer.deploy(name_, symbol_, maxSupply_, admin);
        _register(instance, msg.sender, address(0), KIND_NFT);
        emit InstanceCreated(instance, msg.sender, KIND_NFT, address(0));
    }

    function createCustomNFTDeterministic(
        string calldata name_,
        string calldata symbol_,
        uint256 maxSupply_,
        address admin,
        bytes32 salt
    ) external override returns (address instance) {
        if (admin == address(0)) revert ZeroAddress();
        if (usedSalts[msg.sender][salt]) revert SaltAlreadyUsed();
        usedSalts[msg.sender][salt] = true;
        bytes32 namespacedSalt = keccak256(abi.encode(msg.sender, salt));
        instance = NFTDeployer.deployDeterministic(name_, symbol_, maxSupply_, admin, namespacedSalt);
        _register(instance, msg.sender, address(0), KIND_NFT);
        emit DeterministicNFTCreated(instance, msg.sender, salt);
        emit InstanceCreated(instance, msg.sender, KIND_NFT, address(0));
    }

    function predictCustomNFTAddress(
        address creator,
        string calldata name_,
        string calldata symbol_,
        uint256 maxSupply_,
        address admin,
        bytes32 salt
    ) external view override returns (address) {
        bytes32 namespacedSalt = keccak256(abi.encode(creator, salt));
        bytes32 initCodeHash = NFTDeployer.initCodeHash(name_, symbol_, maxSupply_, admin);
        return address(
            uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), address(this), namespacedSalt, initCodeHash))))
        );
    }

    function createAuctionInstance(address treasury_) external override nonReentrant returns (address instance) {
        if (treasury_ == address(0)) revert ZeroAddress();
        if (treasury_.code.length == 0) revert InvalidContract();
        if (ITreasury(treasury_).factoryController() != address(this)) revert UnauthorizedTreasuryController();
        instance = AuctionDeployer.deployOpen(msg.sender, treasury_, 250);
        ITreasury(treasury_).setAuthorizedPayer(instance, true);
        _register(instance, msg.sender, address(0), KIND_OPEN_AUCTION);
        emit InstanceCreated(instance, msg.sender, KIND_OPEN_AUCTION, address(0));
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
    ) external override nonReentrant returns (address instance) {
        if (owner == address(0) || beneficiary == address(0)) revert ZeroAddress();
        if (nft == address(0) || treasury_ == address(0)) revert ZeroAddress();
        if (nft.code.length == 0 || treasury_.code.length == 0) revert InvalidContract();
        if (msg.sender != beneficiary) revert NotSeller();
        if (ITreasury(treasury_).factoryController() != address(this)) revert UnauthorizedTreasuryController();
        if (ICustomNFT(nft).ownerOf(tokenId) != beneficiary) revert NotSeller();
        ICustomNFT(nft).transferFrom(beneficiary, address(this), tokenId);
        BlindAuctionDeployer.Params memory params;
        params.owner = owner;
        params.beneficiary = beneficiary;
        params.nft = nft;
        params.tokenId = tokenId;
        params.treasury = treasury_;
        params.feeBps = feeBps;
        params.biddingTime = biddingTime;
        params.revealTime = revealTime;
        params.reservePrice = reservePrice;
        instance = BlindAuctionDeployer.deploy(params);
        ICustomNFT(nft).transferFrom(address(this), instance, tokenId);
        ITreasury(treasury_).setAuthorizedPayer(instance, true);
        _register(instance, owner, address(0), KIND_BLIND_AUCTION);
        emit InstanceCreated(instance, owner, KIND_BLIND_AUCTION, address(0));
    }

    function createDutchAuctionInstance(address owner, address treasury_, uint16 feeBps)
        external
        override
        nonReentrant
        returns (address instance)
    {
        if (owner == address(0) || treasury_ == address(0)) revert ZeroAddress();
        if (treasury_.code.length == 0) revert InvalidContract();
        if (ITreasury(treasury_).factoryController() != address(this)) revert UnauthorizedTreasuryController();
        instance = AuctionDeployer.deployDutch(owner, treasury_, feeBps);
        ITreasury(treasury_).setAuthorizedPayer(instance, true);
        _register(instance, owner, address(0), KIND_DUTCH_AUCTION);
        emit InstanceCreated(instance, owner, KIND_DUTCH_AUCTION, address(0));
    }

    function createStaking(address rewardTreasury) external override nonReentrant returns (address instance) {
        if (rewardTreasury == address(0)) revert ZeroAddress();
        if (rewardTreasury.code.length == 0) revert InvalidContract();
        if (ITreasury(rewardTreasury).factoryController() != address(this)) revert UnauthorizedTreasuryController();
        _requireTreasuryAuthority(rewardTreasury);
        instance = StakingDeployer.deploy(msg.sender, rewardTreasury);
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
    ) external override nonReentrant returns (address instance) {
        if (owner == address(0) || treasury_ == address(0)) revert ZeroAddress();
        if (treasury_.code.length == 0) revert InvalidContract();
        if (ITreasury(treasury_).factoryController() != address(this)) revert UnauthorizedTreasuryController();
        RaffleDeployer.Params memory params;
        params.owner = owner;
        params.treasury = treasury_;
        params.feeBps = feeBps;
        params.vrfCoordinator = vrfCoordinator;
        params.subscriptionId = subscriptionId;
        params.keyHash = keyHash;
        params.callbackGasLimit = callbackGasLimit;
        params.requestConfirmations = requestConfirmations;
        params.nativePayment = nativePayment;
        instance = RaffleDeployer.deploy(params);
        ITreasury(treasury_).setAuthorizedPayer(instance, true);
        _register(instance, owner, address(0), KIND_RAFFLE);
        emit InstanceCreated(instance, owner, KIND_RAFFLE, address(0));
    }

    function creatorInstanceCount(address creator) external view override returns (uint256) {
        return instancesByCreator[creator].length;
    }

    function creatorInstanceAt(address creator, uint256 index) external view override returns (address) {
        return instancesByCreator[creator][index];
    }

    function createProtocolSuite(address admin, address feeRecipient)
        external
        override
        nonReentrant
        returns (address, address, address, address, address, address)
    {
        if (admin == address(0) || feeRecipient == address(0)) revert ZeroAddress();
        SuiteDeployment memory suite;
        suite.treasury = CoreDeployer.deployTreasury(address(this), feeRecipient, address(this));
        suite.paymentManager = CoreDeployer.deployPaymentManager(address(this), address(this));
        bytes memory initData = abi.encodeCall(Marketplace.initialize, (admin, suite.treasury, suite.paymentManager));
        suite.marketplace = CoreDeployer.deployProxy(address(marketplaceImplementation), initData);
        suite.auction = AuctionDeployer.deployOpen(admin, suite.treasury, 250);
        suite.dutchAuction = AuctionDeployer.deployDutch(admin, suite.treasury, 250);
        suite.staking = StakingDeployer.deploy(admin, suite.treasury);
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
        _register(suite.auction, msg.sender, address(0), KIND_OPEN_AUCTION);
        _register(suite.dutchAuction, msg.sender, address(0), KIND_DUTCH_AUCTION);
        _register(suite.staking, msg.sender, address(0), KIND_STAKING);
        emit ProtocolSuiteCreated(
            msg.sender, suite.treasury, suite.paymentManager, suite.marketplace, suite.auction, suite.staking
        );
        emit ProtocolSuiteDutchAuctionCreated(msg.sender, suite.treasury, suite.dutchAuction);
        return
            (suite.treasury, suite.paymentManager, suite.marketplace, suite.auction, suite.staking, suite.dutchAuction);
    }

    function finalizeProtocolSuiteControllers(address treasury_, address paymentManager_) external override onlyOwner {
        if (treasury_ == address(0) || paymentManager_ == address(0)) revert ZeroAddress();
        if (ITreasury(treasury_).factoryController() != address(this)) revert UnauthorizedTreasuryController();
        if (IPaymentManager(paymentManager_).factoryController() != address(this)) {
            revert UnauthorizedPaymentManagerController();
        }
        ITreasury(treasury_).setFactoryController(address(0));
        IPaymentManager(paymentManager_).setFactoryController(address(0));
        emit ProtocolSuiteControllersFinalized(treasury_, paymentManager_);
    }

    function transferRegistryOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ZeroAddress();
        registry.setRegistrar(address(this), true);
        registry.transferOwnership(newOwner);
    }

    function _requireTreasuryAuthority(address treasury_) private view {
        Ownable2Step target = Ownable2Step(treasury_);
        if (msg.sender != target.owner() && msg.sender != target.pendingOwner()) revert NotTreasuryAuthority();
    }

    function _register(address instance, address creator, address implementation, bytes32 kind) internal {
        instancesByCreator[creator].push(instance);
        registry.registerInstance(instance, creator, implementation, kind, 1);
    }
}

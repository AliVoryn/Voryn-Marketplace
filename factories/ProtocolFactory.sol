// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import "../core/Marketplace.sol";
import "../core/CustomNFT.sol";
import "../core/OpenAuction.sol";
import "../core/Staking.sol";
import "../core/Treasury.sol";
import "../core/PaymentManager.sol";
import "../registries/ProtocolRegistry.sol";
import "../interfaces/IFactory.sol";

contract ProtocolFactory is Ownable2Step, IFactory {
    bytes32 public constant KIND_MARKETPLACE = keccak256("MARKETPLACE");
    bytes32 public constant KIND_NFT = keccak256("NFT");
    bytes32 public constant KIND_AUCTION = keccak256("AUCTION");
    bytes32 public constant KIND_STAKING = keccak256("STAKING");
    bytes32 public constant KIND_TREASURY = keccak256("TREASURY");
    bytes32 public constant KIND_PAYMENT_MANAGER = keccak256("PAYMENT_MANAGER");

    ProtocolRegistry public immutable registry;
    Marketplace public immutable marketplaceImplementation;

    mapping(address => address[]) private instancesByCreator;
    mapping(address => mapping(bytes32 => bool)) public usedSalts;

    error ZeroAddress();
    error SaltAlreadyUsed();

    event RegistryReferenceSet(address indexed registryAddress);
    event ProtocolSuiteCreated(address indexed creator,address treasury,address paymentManager,address marketplace,address auction,address staking);

    constructor(address initialOwner) Ownable(initialOwner) {
            registry = new ProtocolRegistry(address(this));
            marketplaceImplementation = new Marketplace();
            emit RegistryReferenceSet(address(registry));
    }

    function createTreasury(address feeRecipient) external override returns (address instance) {
        if (feeRecipient == address(0)) revert ZeroAddress();
        Treasury treasury = new Treasury(msg.sender, feeRecipient);
        instance = address(treasury);
        _register(instance, msg.sender, address(0), KIND_TREASURY);
        emit InstanceCreated(instance, msg.sender, KIND_TREASURY, address(0));
    }

    function createPaymentManager() external override returns (address instance) {
        PaymentManager manager = new PaymentManager(msg.sender);
        instance = address(manager);
        _register(instance, msg.sender, address(0), KIND_PAYMENT_MANAGER);
        emit InstanceCreated(instance, msg.sender, KIND_PAYMENT_MANAGER, address(0));
    }

    function createMarketplace(address admin, address treasury, address paymentManager)
        external override returns (address instance)
    {
        if (admin == address(0) || treasury == address(0) || paymentManager == address(0)) revert ZeroAddress();
        bytes memory data = abi.encodeCall(Marketplace.initialize, (admin, treasury, paymentManager));
        ERC1967Proxy proxy = new ERC1967Proxy(address(marketplaceImplementation), data);
        instance = address(proxy);
        _register(instance, msg.sender, address(marketplaceImplementation), KIND_MARKETPLACE);
        emit InstanceCreated(instance, msg.sender, KIND_MARKETPLACE, address(marketplaceImplementation));
    }

    function createCustomNFT(string calldata name_, string calldata symbol_, uint maxSupply_, address admin)
        external override returns (address instance)
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

    function predictCustomNFTAddress(address creator,string calldata name_,string calldata symbol_,uint maxSupply_,address admin,bytes32 salt) external view returns (address) {
        bytes32 namespacedSalt = keccak256(abi.encode(creator, salt));
        bytes32 initCodeHash = keccak256(abi.encodePacked(
            type(CustomNFT).creationCode,
            abi.encode(name_, symbol_, maxSupply_, admin)
        ));
        return address(uint160(uint(keccak256(abi.encodePacked(
            bytes1(0xff), address(this), namespacedSalt, initCodeHash
        )))));
    }

    function createAuctionInstance(address treasury) external override returns (address instance) {
        if (treasury == address(0)) revert ZeroAddress();
        OpenAuction auction = new OpenAuction(msg.sender, treasury, 250);
        instance = address(auction);
        _register(instance, msg.sender, address(0), KIND_AUCTION);
        emit InstanceCreated(instance, msg.sender, KIND_AUCTION, address(0));
    }

    function createStaking(address rewardTreasury) external override returns (address instance) {
        if (rewardTreasury == address(0)) revert ZeroAddress();
        Staking staking = new Staking(msg.sender, rewardTreasury);
        instance = address(staking);
        _register(instance, msg.sender, address(0), KIND_STAKING);
        emit InstanceCreated(instance, msg.sender, KIND_STAKING, address(0));
    }

    function creatorInstanceCount(address creator) external view override returns (uint) {
        return instancesByCreator[creator].length;
    }

    function creatorInstanceAt(address creator, uint index) external view override returns (address) {
        return instancesByCreator[creator][index];
    }


    function createProtocolSuite(address admin,address feeRecipient) external override returns (address treasury,address paymentManager,address marketplace,address auction,address staking) {
        if (admin == address(0) ||feeRecipient == address(0) ZeroAddress();

        Treasury treasuryContract = new Treasury(address(this),feeRecipient);

        PaymentManager paymentManagerContract = new PaymentManager(address(this));

        bytes memory initData = abi.encodeCall(Marketplace.initialize,(admin, address(treasuryContract), address(paymentManagerContract)));

        ERC1967Proxy marketplaceProxy = new ERC1967Proxy(address(marketplaceImplementation),initData);

        OpenAuction auctionContract = new OpenAuction(admin,address(treasuryContract),250);

        Staking stakingContract = new Staking(admin,address(treasuryContract));

        treasuryContract.setAuthorizedPayer(address(marketplaceProxy),true);
        treasuryContract.setAuthorizedPayer(address(auctionContract),true);
        treasuryContract.setAuthorizedPayer(address(stakingContract),true);

        paymentManagerContract.setCreditor(address(marketplaceProxy),true);

        treasuryContract.transferOwnership(admin);
        paymentManagerContract.transferOwnership(admin);

        treasury = address(treasuryContract);
        paymentManager = address(paymentManagerContract);
        marketplace = address(marketplaceProxy);
        auction = address(auctionContract);
        staking = address(stakingContract);

        _register(treasury, msg.sender, address(0), KIND_TREASURY);
        _register(paymentManager, msg.sender, address(0), KIND_PAYMENT_MANAGER);
        _register(marketplace, msg.sender, address(marketplaceImplementation), KIND_MARKETPLACE);
        _register(auction, msg.sender, address(0), KIND_AUCTION);
        _register(staking, msg.sender, address(0), KIND_STAKING);

        emit ProtocolSuiteCreated(msg.sender,treasury,paymentManager,marketplace,auction,staking);
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

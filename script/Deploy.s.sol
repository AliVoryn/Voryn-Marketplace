// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/factory/ProtocolFactory.sol";
import "../src/core/Treasury.sol";
import "../src/core/Raffle.sol";
import "../src/interfaces/ITreasury.sol";

contract DeployScript is Script {
    error ZeroAddress();
    error InvalidVRFConfiguration();

    function run() external {
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);
        address protocolAdmin = vm.envOr("PROTOCOL_ADMIN", deployer);
        address feeRecipient = vm.envOr("FEE_RECIPIENT", deployer);

        if (protocolAdmin == address(0) || feeRecipient == address(0)) revert ZeroAddress();

        vm.startBroadcast(deployerKey);
        ProtocolFactory factory = new ProtocolFactory(deployer);
        console2.log("ProtocolFactory:", address(factory));
        console2.log("ProtocolRegistry:", address(factory.registry()));

        if (vm.envOr("DEPLOY_FULL_SUITE", false)) {
            (
                address treasury_,
                address paymentManager_,
                address marketplace_,
                address auction_,
                address staking_,
                address dutchAuction_
            ) = factory.createProtocolSuite(protocolAdmin, feeRecipient);

            console2.log("Treasury:", treasury_);
            console2.log("PaymentManager:", paymentManager_);
            console2.log("Marketplace:", marketplace_);
            console2.log("OpenAuction:", auction_);
            console2.log("DutchAuction:", dutchAuction_);
            console2.log("Staking:", staking_);

            if (vm.envOr("DEPLOY_RAFFLE", false)) {
                address raffle = _deployRaffle(factory, treasury_, protocolAdmin);
                console2.log("Raffle:", raffle);
            }

            factory.finalizeProtocolSuiteControllers(treasury_, paymentManager_);
            console2.log("Suite controllers finalized.");
        }

        console2.log("ProtocolAdmin:", protocolAdmin);
        vm.stopBroadcast();
    }

    function _deployRaffle(ProtocolFactory factory, address treasury_, address defaultOwner)
        private
        returns (address raffle)
    {
        address vrfCoordinator = vm.envAddress("VRF_COORDINATOR");
        uint256 subscriptionId = vm.envUint("VRF_SUBSCRIPTION_ID");
        bytes32 keyHash = vm.envBytes32("VRF_KEY_HASH");
        uint32 callbackGasLimit = uint32(vm.envOr("VRF_CALLBACK_GAS_LIMIT", uint256(500_000)));
        uint16 requestConfirmations = uint16(vm.envOr("VRF_REQUEST_CONFIRMATIONS", uint256(3)));
        bool nativePayment = vm.envOr("VRF_NATIVE_PAYMENT", false);
        uint16 feeBps = uint16(vm.envOr("RAFFLE_FEE_BPS", uint256(250)));
        address owner = vm.envOr("RAFFLE_OWNER", defaultOwner);

        if (
            vrfCoordinator == address(0) || subscriptionId == 0 || keyHash == bytes32(0) || callbackGasLimit == 0
                || requestConfirmations < 3 || requestConfirmations > 200 || owner == address(0)
        ) revert InvalidVRFConfiguration();

        raffle = factory.createRaffleInstance(
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
    }
}

contract DeployRaffleScript is Script {
    error InvalidFactoryController();

    function run() external returns (address raffle) {
        address factoryAddr = vm.envAddress("FACTORY_ADDRESS");
        address treasuryAddr = vm.envAddress("TREASURY_ADDRESS");
        address vrfCoordinator = vm.envAddress("VRF_COORDINATOR");
        uint256 subscriptionId = vm.envUint("VRF_SUBSCRIPTION_ID");
        bytes32 keyHash = vm.envBytes32("VRF_KEY_HASH");
        uint32 callbackGasLimit = uint32(vm.envOr("VRF_CALLBACK_GAS_LIMIT", uint256(500_000)));
        uint16 requestConfirmations = uint16(vm.envOr("VRF_REQUEST_CONFIRMATIONS", uint256(3)));
        bool nativePayment = vm.envOr("VRF_NATIVE_PAYMENT", false);
        uint16 feeBps = uint16(vm.envOr("RAFFLE_FEE_BPS", uint256(250)));
        address owner = vm.envOr("RAFFLE_OWNER", vm.envAddress("PROTOCOL_ADMIN"));

        if (ITreasury(treasuryAddr).factoryController() != factoryAddr) revert InvalidFactoryController();

        vm.startBroadcast();
        raffle = ProtocolFactory(factoryAddr)
            .createRaffleInstance(
                owner,
                treasuryAddr,
                feeBps,
                vrfCoordinator,
                subscriptionId,
                keyHash,
                callbackGasLimit,
                requestConfirmations,
                nativePayment
            );
        vm.stopBroadcast();

        console2.log("Raffle:", raffle);
        console2.log("VRF subscription:", subscriptionId);
    }
}

contract PrepareOwnershipTransferScript is Script {
    function run() external {
        address factoryAddr = vm.envAddress("FACTORY_ADDRESS");
        address protocolAdmin = vm.envAddress("PROTOCOL_ADMIN");

        ProtocolFactory factory = ProtocolFactory(factoryAddr);
        vm.startBroadcast();
        factory.transferRegistryOwnership(protocolAdmin);
        factory.transferOwnership(protocolAdmin);
        vm.stopBroadcast();

        console2.log("Factory and Registry ownership pending for:", protocolAdmin);
    }
}

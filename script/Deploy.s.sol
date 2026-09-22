pragma solidity ^0.8.24;
import "forge-std/Script.sol";
import "../src/factory/ProtocolFactory.sol";
import "../src/registries/ProtocolRegistry.sol";
contract DeployScript is Script {
    function run() external {
        address deployer = vm.envAddress("DEPLOYER_ADDRESS");
        address protocolAdmin = vm.envOr("PROTOCOL_ADMIN", deployer);
        address feeRecipient = vm.envOr("FEE_RECIPIENT", deployer);
        vm.startBroadcast();
        ProtocolFactory factory = new ProtocolFactory(deployer);
        console2.log("ProtocolFactory deployed at:", address(factory));
        console2.log("ProtocolRegistry deployed at:", address(factory.registry()));
        bool deploySuite = vm.envOr("DEPLOY_FULL_SUITE", false);
        if (deploySuite) {
            (address treasury_, address paymentManager_, address marketplace_, address auction_, address staking_, address dutchAuction_) =
                factory.createProtocolSuite(protocolAdmin, feeRecipient);
            console2.log("Treasury:       ", treasury_);
            console2.log("PaymentManager: ", paymentManager_);
            console2.log("Marketplace:    ", marketplace_);
            console2.log("OpenAuction:    ", auction_);
            console2.log("DutchAuction:   ", dutchAuction_);
            console2.log("Staking:        ", staking_);
            console2.log("");
            console2.log("Treasury and PaymentManager ownership is pending for:", protocolAdmin);
            console2.log("Run AcceptOwnershipScript from the protocol admin account.");
        }
        factory.transferRegistryOwnership(protocolAdmin);
        factory.transferOwnership(protocolAdmin);
        console2.log("Factory and Registry ownership is pending for:", protocolAdmin);
        vm.stopBroadcast();
    }
}
contract DeployRaffleScript is Script {
    function run() external {
        address factoryAddr = vm.envAddress("FACTORY_ADDRESS");
        address treasuryAddr = vm.envAddress("TREASURY_ADDRESS");
        address vrfCoordinator = vm.envAddress("VRF_COORDINATOR"); 
        uint256 subscriptionId = vm.envUint("VRF_SUBSCRIPTION_ID"); 
        bytes32 keyHash = vm.envBytes32("VRF_KEY_HASH"); 
        uint32 callbackGasLimit = uint32(vm.envOr("VRF_CALLBACK_GAS_LIMIT", uint256(200_000)));
        uint16 requestConfirmations = uint16(vm.envOr("VRF_REQUEST_CONFIRMATIONS", uint256(3)));
        bool nativePayment = vm.envOr("VRF_NATIVE_PAYMENT", false);
        uint16 feeBps = uint16(vm.envOr("RAFFLE_FEE_BPS", uint256(250)));
        address owner = vm.envOr("RAFFLE_OWNER", vm.envAddress("PROTOCOL_ADMIN"));
        ProtocolFactory factory = ProtocolFactory(factoryAddr);
        vm.startBroadcast();
        address raffle = factory.createRaffleInstance(
            owner, treasuryAddr, feeBps, vrfCoordinator, subscriptionId, keyHash, callbackGasLimit, requestConfirmations, nativePayment
        );
        vm.stopBroadcast();
        console2.log("Raffle deployed at:", raffle);
        console2.log("");
        console2.log("REQUIRED MANUAL STEP: add this address as a consumer on");
        console2.log("VRF subscription", subscriptionId, "before opening ticket sales.");
        console2.log("See RAFFLE_INTEGRATION.md for the full operational checklist.");
    }
}

contract AcceptOwnershipScript is Script {
    function run() external {
        address factoryAddr = vm.envAddress("FACTORY_ADDRESS");
        address registryAddr = vm.envAddress("REGISTRY_ADDRESS");
        address treasuryAddr = vm.envAddress("TREASURY_ADDRESS");
        address paymentManagerAddr = vm.envAddress("PAYMENT_MANAGER_ADDRESS");

        vm.startBroadcast();
        ProtocolFactory(factoryAddr).acceptOwnership();
        ProtocolRegistry(registryAddr).acceptOwnership();
        Treasury(payable(treasuryAddr)).acceptOwnership();
        PaymentManager(payable(paymentManagerAddr)).acceptOwnership();
        vm.stopBroadcast();

        console2.log("Factory:", factoryAddr);
        console2.log("Registry, Treasury, and PaymentManager ownership accepted.");
    }
}

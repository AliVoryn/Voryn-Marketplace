// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/automation/ProtocolAutomationReceiver.sol";

contract DeployAutomationReceiver is Script {
    function run() external returns (ProtocolAutomationReceiver receiver) {
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address admin = vm.envAddress("AUTOMATION_ADMIN");
        address forwarder = vm.envAddress("CHAINLINK_FORWARDER");
        address registry = vm.envAddress("PROTOCOL_REGISTRY");
        uint64 chainSelector = uint64(vm.envUint("CHAIN_SELECTOR"));

        vm.startBroadcast(deployerKey);
        receiver = new ProtocolAutomationReceiver(admin, forwarder, registry, chainSelector);
        vm.stopBroadcast();
    }
}

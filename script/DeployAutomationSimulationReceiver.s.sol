// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/automation/ProtocolAutomationSimulationReceiver.sol";

contract DeployAutomationSimulationReceiver is Script {
    function _isKnownTestnet(uint256 id) internal pure returns (bool) {
        return id == 11155111 || id == 84532 || id == 421614 || id == 11155420 || id == 80002 || id == 43113 || id == 97;
    }

    function run() external returns (ProtocolAutomationSimulationReceiver receiver) {
        require(_isKnownTestnet(block.chainid), "simulation receiver: testnets only");
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address admin = vm.envAddress("AUTOMATION_ADMIN");
        address mockForwarder = vm.envAddress("CHAINLINK_MOCK_FORWARDER");
        address registry = vm.envAddress("PROTOCOL_REGISTRY");
        uint64 chainSelector = uint64(vm.envUint("CHAIN_SELECTOR"));

        vm.startBroadcast(deployerKey);
        receiver = new ProtocolAutomationSimulationReceiver(admin, mockForwarder, registry, chainSelector);
        vm.stopBroadcast();
    }
}

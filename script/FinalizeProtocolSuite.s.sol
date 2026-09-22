// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/factory/ProtocolFactory.sol";

contract FinalizeProtocolSuiteScript is Script {
    function run() external {
        address factory = vm.envAddress("FACTORY_ADDRESS");
        address treasury = vm.envAddress("TREASURY_ADDRESS");
        address paymentManager = vm.envAddress("PAYMENT_MANAGER_ADDRESS");
        vm.startBroadcast();
        ProtocolFactory(factory).finalizeProtocolSuiteControllers(treasury, paymentManager);
        vm.stopBroadcast();
    }
}

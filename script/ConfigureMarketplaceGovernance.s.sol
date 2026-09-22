// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/core/Marketplace.sol";

contract ConfigureMarketplaceGovernanceScript is Script {
    error ZeroAddress();

    function run() external {
        Marketplace marketplace = Marketplace(vm.envAddress("MARKETPLACE_ADDRESS"));
        address timelock = vm.envAddress("GOVERNANCE_TIMELOCK");
        address operator = vm.envAddress("GOVERNANCE_OPERATOR");
        address currentAdmin = vm.envAddress("PROTOCOL_ADMIN");
        if (timelock == address(0) || operator == address(0) || currentAdmin == address(0)) revert ZeroAddress();

        vm.startBroadcast();
        marketplace.grantRole(marketplace.DEFAULT_ADMIN_ROLE(), timelock);
        marketplace.grantRole(marketplace.ADMIN_ROLE(), timelock);
        marketplace.grantRole(marketplace.OPERATOR_ROLE(), operator);
        if (currentAdmin != timelock) {
            marketplace.revokeRole(marketplace.ADMIN_ROLE(), currentAdmin);
            if (operator != currentAdmin) marketplace.revokeRole(marketplace.OPERATOR_ROLE(), currentAdmin);
            marketplace.revokeRole(marketplace.DEFAULT_ADMIN_ROLE(), currentAdmin);
        }
        vm.stopBroadcast();
    }
}

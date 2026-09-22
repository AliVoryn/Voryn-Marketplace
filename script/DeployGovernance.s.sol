// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/governance/ProtocolGovernance.sol";

contract DeployGovernanceScript is Script {
    error InvalidConfiguration();

    function run() external returns (address timelock) {
        uint256 minDelay = vm.envUint("GOVERNANCE_MIN_DELAY");
        address proposer = vm.envAddress("GOVERNANCE_PROPOSER");
        address executor = vm.envAddress("GOVERNANCE_EXECUTOR");
        address admin = vm.envAddress("GOVERNANCE_ADMIN");
        if (proposer == address(0)) revert InvalidConfiguration();
        address[] memory proposers = new address[](1);
        address[] memory executors = new address[](1);
        proposers[0] = proposer;
        executors[0] = executor;
        vm.startBroadcast();
        timelock = address(new ProtocolTimelock(minDelay, proposers, executors, admin));
        vm.stopBroadcast();
        console2.log("ProtocolTimelock:", timelock);
    }
}

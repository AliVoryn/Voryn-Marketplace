// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import { IVRFSubscriptionV2Plus } from "@chainlink/contracts/src/v0.8/vrf/dev/interfaces/IVRFSubscriptionV2Plus.sol";

contract CreateVRFSubscriptionScript is Script {
    error InvalidCoordinator();

    function run() external returns (uint256 subscriptionId) {
        address coordinator = vm.envAddress("VRF_COORDINATOR");
        if (coordinator == address(0) || coordinator.code.length == 0) revert InvalidCoordinator();
        uint256 funding = vm.envOr("VRF_NATIVE_FUNDING", uint256(0));
        vm.startBroadcast();
        subscriptionId = IVRFSubscriptionV2Plus(coordinator).createSubscription();
        if (funding != 0) {
            IVRFSubscriptionV2Plus(coordinator).fundSubscriptionWithNative{ value: funding }(subscriptionId);
        }
        vm.stopBroadcast();
        console2.log("VRF subscription:", subscriptionId);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import { IVRFSubscriptionV2Plus } from "@chainlink/contracts/src/v0.8/vrf/dev/interfaces/IVRFSubscriptionV2Plus.sol";

contract FundVRFSubscriptionScript is Script {
    error InvalidCoordinator();
    error InvalidFunding();

    function run() external {
        address coordinator = vm.envAddress("VRF_COORDINATOR");
        uint256 subscriptionId = vm.envUint("VRF_SUBSCRIPTION_ID");
        uint256 amount = vm.envUint("VRF_NATIVE_FUNDING");
        if (coordinator == address(0) || coordinator.code.length == 0) revert InvalidCoordinator();
        if (subscriptionId == 0 || amount == 0) revert InvalidFunding();
        vm.startBroadcast();
        IVRFSubscriptionV2Plus(coordinator).fundSubscriptionWithNative{ value: amount }(subscriptionId);
        vm.stopBroadcast();
    }
}

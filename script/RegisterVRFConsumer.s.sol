// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import { IVRFSubscriptionV2Plus } from "@chainlink/contracts/src/v0.8/vrf/dev/interfaces/IVRFSubscriptionV2Plus.sol";

contract RegisterVRFConsumerScript is Script {
    error InvalidConfiguration();

    function run() external {
        address coordinator = vm.envAddress("VRF_COORDINATOR");
        uint256 subscriptionId = vm.envUint("VRF_SUBSCRIPTION_ID");
        address consumer = vm.envAddress("RAFFLE_ADDRESS");
        if (
            coordinator == address(0) || coordinator.code.length == 0 || subscriptionId == 0 || consumer == address(0)
                || consumer.code.length == 0
        ) {
            revert InvalidConfiguration();
        }
        vm.startBroadcast();
        IVRFSubscriptionV2Plus(coordinator).addConsumer(subscriptionId, consumer);
        vm.stopBroadcast();
        console2.log("VRF consumer:", consumer);
    }
}

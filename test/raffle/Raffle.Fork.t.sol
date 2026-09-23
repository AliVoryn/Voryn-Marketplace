// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../../src/core/Raffle.sol";

contract RaffleForkSmokeTest is Test {
    function testFork_DeploymentConfigurationMatchesTargetChain() public {
        string memory rpcUrl = vm.envOr("FORK_RPC_URL", string(""));
        address raffleAddress = vm.envOr("RAFFLE_ADDRESS", address(0));
        address coordinator = vm.envOr("VRF_COORDINATOR", address(0));
        uint256 subscriptionId = vm.envOr("VRF_SUBSCRIPTION_ID", uint256(0));
        uint32 callbackGasLimit = uint32(vm.envOr("VRF_CALLBACK_GAS_LIMIT", uint256(0)));
        uint16 requestConfirmations = uint16(vm.envOr("VRF_REQUEST_CONFIRMATIONS", uint256(0)));

        if (bytes(rpcUrl).length == 0 || raffleAddress == address(0) || coordinator == address(0)) {
            vm.skip(true);
        }

        vm.createSelectFork(rpcUrl);

        Raffle raffle = Raffle(payable(raffleAddress));
        assertGt(coordinator.code.length, 0);
        assertEq(raffle.vrfCoordinator(), coordinator);
        assertEq(raffle.subscriptionId(), subscriptionId);
        assertEq(raffle.callbackGasLimit(), callbackGasLimit);
        assertEq(raffle.requestConfirmations(), requestConfirmations);
    }
}

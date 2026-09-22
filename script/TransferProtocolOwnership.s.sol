// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";

interface IOwnableTransfer {
    function transferOwnership(address newOwner) external;
}

contract TransferProtocolOwnershipScript is Script {
    error ZeroAddress();
    error NoTargets();

    function run() external {
        address newOwner = vm.envAddress("GOVERNANCE_TIMELOCK");
        if (newOwner == address(0)) revert ZeroAddress();

        address[] memory targets = _targets();
        vm.startBroadcast();
        for (uint256 i; i < targets.length; ++i) {
            IOwnableTransfer(targets[i]).transferOwnership(newOwner);
        }
        vm.stopBroadcast();
    }

    function _targets() private view returns (address[] memory targets) {
        address[] memory configured = new address[](9);
        configured[0] = vm.envOr("FACTORY_ADDRESS", address(0));
        configured[1] = vm.envOr("REGISTRY_ADDRESS", address(0));
        configured[2] = vm.envOr("TREASURY_ADDRESS", address(0));
        configured[3] = vm.envOr("PAYMENT_MANAGER_ADDRESS", address(0));
        configured[4] = vm.envOr("OPEN_AUCTION_ADDRESS", address(0));
        configured[5] = vm.envOr("BLIND_AUCTION_ADDRESS", address(0));
        configured[6] = vm.envOr("DUTCH_AUCTION_ADDRESS", address(0));
        configured[7] = vm.envOr("STAKING_ADDRESS", address(0));
        configured[8] = vm.envOr("RAFFLE_ADDRESS", address(0));

        uint256 count;
        for (uint256 i; i < configured.length; ++i) {
            if (configured[i] != address(0)) ++count;
        }
        if (count == 0) revert NoTargets();

        targets = new address[](count);
        uint256 cursor;
        for (uint256 i; i < configured.length; ++i) {
            if (configured[i] == address(0)) continue;
            targets[cursor++] = configured[i];
        }
    }
}

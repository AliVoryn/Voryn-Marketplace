// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";

contract PreflightScript is Script {
    error WrongChain(uint256 expected, uint256 actual);
    error ZeroAddress(bytes32 name);
    error InvalidFee(uint256 feeBps);
    error InvalidConfirmationCount(uint256 confirmations);

    function run() external view {
        uint256 expectedChainId = vm.envUint("EXPECTED_CHAIN_ID");
        if (block.chainid != expectedChainId) revert WrongChain(expectedChainId, block.chainid);
        if (vm.envUint("DEPLOYER_PRIVATE_KEY") == 0) revert ZeroAddress("DEPLOYER");
        _requireNonZero("PROTOCOL_ADMIN", "PROTOCOL_ADMIN");
        _requireNonZero("FEE_RECIPIENT", "FEE_RECIPIENT");
        uint256 feeBps = vm.envOr("RAFFLE_FEE_BPS", uint256(250));
        if (feeBps > 1000) revert InvalidFee(feeBps);
        uint256 confirmations = vm.envOr("VRF_REQUEST_CONFIRMATIONS", uint256(3));
        if (confirmations < 3 || confirmations > 200) revert InvalidConfirmationCount(confirmations);
    }

    function _requireNonZero(string memory name, bytes32 label) private view {
        if (vm.envAddress(name) == address(0)) revert ZeroAddress(label);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { ProtocolAutomationReceiver } from "./ProtocolAutomationReceiver.sol";

contract ProtocolAutomationSimulationReceiver is ProtocolAutomationReceiver {
    constructor(address initialOwner, address mockForwarder_, address registry_, uint64 chainSelector_)
        ProtocolAutomationReceiver(initialOwner, mockForwarder_, registry_, chainSelector_)
    { }

    function isSimulationReceiver() external pure returns (bool) {
        return true;
    }

    function _requiresWorkflowIdentity() internal pure override returns (bool) {
        return false;
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/automation/ProtocolAutomationReceiver.sol";

contract ConfigureAutomationReceiver is Script {
    function run() external {
        uint256 ownerKey = vm.envUint("AUTOMATION_OWNER_PRIVATE_KEY");
        ProtocolAutomationReceiver receiver = ProtocolAutomationReceiver(vm.envAddress("AUTOMATION_RECEIVER"));
        bytes32 workflowId = vm.envBytes32("CRE_WORKFLOW_ID");
        address workflowAuthor = vm.envAddress("CRE_WORKFLOW_AUTHOR");

        vm.startBroadcast(ownerKey);
        receiver.setExpectedWorkflowId(workflowId);
        receiver.setExpectedAuthor(workflowAuthor);
        receiver.unpauseAutomation();
        vm.stopBroadcast();
    }
}

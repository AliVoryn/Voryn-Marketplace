// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../support/AutomationIntegrationBase.sol";
import "../../src/automation/ProtocolAutomationSimulationReceiver.sol";
import "../../script/DeployAutomationReceiver.s.sol";
import "../../script/DeployAutomationSimulationReceiver.s.sol";
import "../../script/ConfigureAutomationReceiver.s.sol";

contract AutomationScriptsTest is AutomationIntegrationBase {
    uint256 internal constant KEY = 0xA11CE;

    function _env() internal {
        vm.setEnv("DEPLOYER_PRIVATE_KEY", vm.toString(KEY));
        vm.setEnv("AUTOMATION_ADMIN", vm.toString(vm.addr(KEY)));
        vm.setEnv("CHAINLINK_FORWARDER", vm.toString(address(forwarder)));
        vm.setEnv("CHAINLINK_MOCK_FORWARDER", vm.toString(address(forwarder)));
        vm.setEnv("PROTOCOL_REGISTRY", vm.toString(address(registry)));
        vm.setEnv("CHAIN_SELECTOR", vm.toString(uint256(CHAIN_SELECTOR)));
    }

    function test_DeployScriptCreatesPausedProductionReceiver() public {
        _env();
        ProtocolAutomationReceiver deployed = new DeployAutomationReceiver().run();
        assertEq(deployed.owner(), vm.addr(KEY));
        assertTrue(deployed.paused());
        assertEq(deployed.getForwarderAddress(), address(forwarder));
        assertEq(address(deployed.registry()), address(registry));
        assertEq(deployed.expectedChainSelector(), CHAIN_SELECTOR);
    }

    function test_SimulationDeployScriptRefusesMainnetsAndAcceptsTestnets() public {
        _env();
        DeployAutomationSimulationReceiver script = new DeployAutomationSimulationReceiver();
        uint256[4] memory mainnets = [uint256(1), 10, 8453, 42161];
        for (uint256 i; i < mainnets.length; ++i) {
            vm.chainId(mainnets[i]);
            vm.expectRevert(bytes("simulation receiver: testnets only"));
            script.run();
        }
        uint256[7] memory testnets = [uint256(11155111), 84532, 421614, 11155420, 80002, 43113, 97];
        for (uint256 i; i < testnets.length; ++i) {
            vm.chainId(testnets[i]);
            ProtocolAutomationSimulationReceiver sim = script.run();
            assertTrue(sim.isSimulationReceiver());
            assertTrue(sim.paused());
            assertEq(sim.owner(), vm.addr(KEY));
        }
    }

    function test_ConfigureScriptSetsIdentityAndUnpauses() public {
        _env();
        ProtocolAutomationReceiver deployed = new DeployAutomationReceiver().run();
        address author = makeAddr("script-author");
        bytes32 workflowId = keccak256("script-workflow");
        vm.setEnv("AUTOMATION_OWNER_PRIVATE_KEY", vm.toString(KEY));
        vm.setEnv("AUTOMATION_RECEIVER", vm.toString(address(deployed)));
        vm.setEnv("CRE_WORKFLOW_ID", vm.toString(workflowId));
        vm.setEnv("CRE_WORKFLOW_AUTHOR", vm.toString(author));
        new ConfigureAutomationReceiver().run();
        assertFalse(deployed.paused());
        assertTrue(deployed.workflowConfigured());
        assertEq(deployed.getExpectedWorkflowId(), workflowId);
        assertEq(deployed.getExpectedAuthor(), author);
    }
}

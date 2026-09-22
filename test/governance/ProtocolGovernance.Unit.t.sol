// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../../src/governance/ProtocolGovernance.sol";

contract ProtocolGovernanceTest is Test {
    ProtocolTimelock internal timelock;
    address internal admin = makeAddr("governance-admin");
    address internal proposer = makeAddr("governance-proposer");
    address internal executor = makeAddr("governance-executor");

    function setUp() public {
        address[] memory proposers = new address[](1);
        address[] memory executors = new address[](1);
        proposers[0] = proposer;
        executors[0] = executor;
        timelock = new ProtocolTimelock(2 days, proposers, executors, admin);
    }

    function test_ConstructorConfiguresExpectedRoles() public view {
        assertTrue(timelock.hasRole(timelock.PROPOSER_ROLE(), proposer));
        assertTrue(timelock.hasRole(timelock.EXECUTOR_ROLE(), executor));
        assertTrue(timelock.hasRole(timelock.DEFAULT_ADMIN_ROLE(), admin));
        assertEq(timelock.getMinDelay(), 2 days);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../../src/governance/ProtocolGovernance.sol";

contract ProtocolGovernanceSecurityTest is Test {
    ProtocolTimelock internal timelock;
    address internal proposer = makeAddr("proposer");
    address internal executor = makeAddr("executor");
    address internal admin = makeAddr("admin");

    function setUp() public {
        address[] memory proposers = new address[](1);
        proposers[0] = proposer;
        address[] memory executors = new address[](1);
        executors[0] = executor;
        timelock = new ProtocolTimelock(1 days, proposers, executors, admin);
    }

    function test_UnauthorizedCannotSchedule() public {
        vm.prank(executor);
        vm.expectRevert();
        timelock.schedule(address(1), 0, "", bytes32(0), bytes32(uint256(1)), 1 days);
    }

    function test_ExecutorCannotExecuteBeforeDelay() public {
        bytes memory data = abi.encodeWithSignature("acceptOwnership()");
        bytes32 predecessor = bytes32(0);
        bytes32 salt = bytes32(uint256(2));
        vm.prank(proposer);
        timelock.schedule(address(timelock), 0, data, predecessor, salt, 1 days);
        vm.prank(executor);
        vm.expectRevert();
        timelock.execute(address(timelock), 0, data, predecessor, salt);
    }
}

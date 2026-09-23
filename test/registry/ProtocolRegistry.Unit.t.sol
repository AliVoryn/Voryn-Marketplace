// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../support/TestBase.sol";

contract ProtocolRegistryUnitTest is ProtocolTestBase {
    ProtocolRegistry internal registry;
    bytes32 internal constant KIND = keccak256("UNIT");

    function setUp() public {
        registry = new ProtocolRegistry(admin);
    }

    function test_RegisterRejectsZeroInstance() public {
        vm.prank(admin);
        vm.expectRevert(ProtocolRegistry.InvalidInstance.selector);
        registry.registerInstance(address(0), seller, address(0), KIND, 1);
    }

    function test_RegisterRejectsEOAInstance() public {
        vm.prank(admin);
        vm.expectRevert(ProtocolRegistry.InvalidInstance.selector);
        registry.registerInstance(attacker, seller, address(0), KIND, 1);
    }

    function test_RegisterRejectsZeroCreator() public {
        address instance = address(new RegistryUnitMock());
        vm.prank(admin);
        vm.expectRevert(ProtocolRegistry.InvalidCreator.selector);
        registry.registerInstance(instance, address(0), address(0), KIND, 1);
    }

    function test_RegisterRejectsEOAImplementation() public {
        address instance = address(new RegistryUnitMock());
        vm.prank(admin);
        vm.expectRevert(ProtocolRegistry.InvalidImplementation.selector);
        registry.registerInstance(instance, seller, attacker, KIND, 1);
    }

    function test_RegisterRejectsZeroVersion() public {
        address instance = address(new RegistryUnitMock());
        vm.prank(admin);
        vm.expectRevert(ProtocolRegistry.InvalidVersion.selector);
        registry.registerInstance(instance, seller, address(0), KIND, 0);
    }

    function test_RegisterRejectsDuplicateInstance() public {
        address instance = address(new RegistryUnitMock());
        vm.prank(admin);
        registry.registerInstance(instance, seller, address(0), KIND, 1);
        vm.prank(admin);
        vm.expectRevert(IRegistry.AlreadyRegistered.selector);
        registry.registerInstance(instance, seller, address(0), KIND, 1);
    }

    function test_SetActiveRejectsUnknownInstance() public {
        vm.prank(admin);
        vm.expectRevert(IRegistry.UnknownInstance.selector);
        registry.setActive(attacker, false);
    }
}

contract RegistryUnitMock { }

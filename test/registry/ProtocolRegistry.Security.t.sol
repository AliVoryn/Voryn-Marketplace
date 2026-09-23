// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../support/TestBase.sol";

contract ProtocolRegistrySecurityTest is ProtocolTestBase {
    ProtocolRegistry internal registry;
    bytes32 internal constant KIND = keccak256("SECURITY");

    function setUp() public {
        registry = new ProtocolRegistry(admin);
    }

    function test_ExplicitRegistrarCanRegister() public {
        vm.prank(admin);
        registry.setRegistrar(attacker, true);
        address instance = address(new RegistrySecurityMock());
        vm.prank(attacker);
        registry.registerInstance(instance, seller, address(0), KIND, 1);
        assertTrue(registry.isRegistered(instance));
    }

    function test_RegistrarCannotChangeActivation() public {
        vm.prank(admin);
        registry.setRegistrar(attacker, true);
        address instance = address(new RegistrySecurityMock());
        vm.prank(attacker);
        registry.registerInstance(instance, seller, address(0), KIND, 1);
        vm.prank(attacker);
        vm.expectRevert();
        registry.setActive(instance, false);
    }

    function test_NonRegistrarCannotRegister() public {
        address instance = address(new RegistrySecurityMock());
        vm.prank(attacker);
        vm.expectRevert(ProtocolRegistry.UnauthorizedRegistrar.selector);
        registry.registerInstance(instance, seller, address(0), KIND, 1);
    }

    function test_ExplicitRegistrarCannotRegisterAfterRevocation() public {
        vm.prank(admin);
        registry.setRegistrar(attacker, true);
        vm.prank(admin);
        registry.setRegistrar(attacker, false);
        address instance = address(new RegistrySecurityMock());
        vm.prank(attacker);
        vm.expectRevert(ProtocolRegistry.UnauthorizedRegistrar.selector);
        registry.registerInstance(instance, seller, address(0), KIND, 1);
    }
}

contract RegistrySecurityMock { }

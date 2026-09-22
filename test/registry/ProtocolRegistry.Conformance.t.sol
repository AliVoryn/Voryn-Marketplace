// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../support/TestBase.sol";

contract RegistryInstance { }

contract RegistryImplementation { }

contract ProtocolRegistryConformanceTest is ProtocolTestBase {
    ProtocolRegistry internal registry;
    bytes32 internal constant KIND = keccak256("TEST");

    function setUp() public {
        registry = new ProtocolRegistry(admin);
    }

    function test_RegisterAndQueryAllIndexes() public {
        RegistryInstance firstInstance = new RegistryInstance();
        RegistryInstance secondInstance = new RegistryInstance();
        RegistryImplementation firstImplementation = new RegistryImplementation();
        RegistryImplementation secondImplementation = new RegistryImplementation();
        address first = address(firstInstance);
        address second = address(secondInstance);

        vm.prank(admin);
        registry.registerInstance(first, seller, address(firstImplementation), KIND, 1);
        vm.prank(admin);
        registry.registerInstance(second, seller, address(secondImplementation), KIND, 2);

        IRegistry.Record memory record = registry.getRecord(first);
        assertEq(record.instance, first);
        assertEq(record.creator, seller);
        assertEq(record.implementation, address(firstImplementation));
        assertEq(record.kind, KIND);
        assertEq(record.version, 1);
        assertTrue(record.active);
        assertTrue(registry.isRegistered(first));
        assertEq(registry.allCount(), 2);
        assertEq(registry.byKindCount(KIND), 2);
        assertEq(registry.byCreatorCount(seller), 2);
        assertTrue(registry.allAt(0) == first || registry.allAt(0) == second);
        assertTrue(registry.allAt(1) == first || registry.allAt(1) == second);
        assertTrue(registry.kindAt(KIND, 0) == first || registry.kindAt(KIND, 0) == second);
        assertTrue(registry.creatorAt(seller, 0) == first || registry.creatorAt(seller, 0) == second);
    }

    function test_RegisterRejectsUnauthorizedZeroAndDuplicate() public {
        RegistryInstance unauthorizedInstance = new RegistryInstance();
        vm.prank(attacker);
        vm.expectRevert(ProtocolRegistry.UnauthorizedRegistrar.selector);
        registry.registerInstance(address(unauthorizedInstance), seller, address(0), KIND, 1);

        vm.prank(admin);
        vm.expectRevert(IRegistry.ZeroAddress.selector);
        registry.setRegistrar(address(0), true);

        RegistryInstance instance = new RegistryInstance();
        vm.prank(admin);
        registry.registerInstance(address(instance), seller, address(0), KIND, 1);
        vm.prank(admin);
        vm.expectRevert(IRegistry.AlreadyRegistered.selector);
        registry.registerInstance(address(instance), seller, address(0), KIND, 1);
    }

    function test_RegistrarCanRegisterAndCanBeRevoked() public {
        address registrar = makeAddr("registrar");
        vm.prank(admin);
        registry.setRegistrar(registrar, true);

        address instance = address(new RegistryInstance());
        vm.prank(registrar);
        registry.registerInstance(instance, seller, address(0), KIND, 1);

        vm.prank(admin);
        registry.setRegistrar(registrar, false);

        address secondInstance = address(new RegistryInstance());
        vm.prank(registrar);
        vm.expectRevert(ProtocolRegistry.UnauthorizedRegistrar.selector);
        registry.registerInstance(secondInstance, seller, address(0), KIND, 1);
    }

    function test_SetActiveAndUnknownInstanceBoundaries() public {
        address instance = makeAddr("instance");
        vm.prank(admin);
        vm.expectRevert(IRegistry.UnknownInstance.selector);
        registry.setActive(instance, false);
        vm.expectRevert(IRegistry.UnknownInstance.selector);
        registry.getRecord(instance);

        RegistryInstance deployedInstance = new RegistryInstance();
        instance = address(deployedInstance);
        vm.prank(admin);
        registry.registerInstance(instance, seller, address(0), KIND, 1);
        vm.prank(attacker);
        vm.expectRevert();
        registry.setActive(instance, false);
        vm.prank(admin);
        registry.setActive(instance, false);
        assertFalse(registry.getRecord(instance).active);
        vm.prank(admin);
        registry.setActive(instance, true);
        assertTrue(registry.getRecord(instance).active);
    }

    function test_TransferOwnershipPreservesRegistryControl() public {
        vm.prank(admin);
        registry.transferOwnership(seller);
        vm.prank(seller);
        registry.acceptOwnership();
        address instance = address(new RegistryInstance());
        vm.prank(seller);
        registry.registerInstance(instance, seller, address(0), KIND, 1);
        assertTrue(registry.isRegistered(instance));
    }

    function test_TransferOwnershipPreservesExplicitRegistrarPrivilege() public {
        address registrar = makeAddr("persistentRegistrar");
        vm.prank(admin);
        registry.setRegistrar(registrar, true);
        vm.prank(admin);
        registry.transferOwnership(seller);
        vm.prank(seller);
        registry.acceptOwnership();
        assertTrue(registry.registrar(registrar));

        address instance = address(new RegistryInstance());
        vm.prank(registrar);
        registry.registerInstance(instance, seller, address(0), KIND, 1);
    }

    function test_TransferOwnershipDoesNotGrantFormerOwnerRegistrarPrivilege() public {
        vm.prank(admin);
        registry.transferOwnership(seller);
        vm.prank(seller);
        registry.acceptOwnership();

        RegistryInstance formerOwnerInstance = new RegistryInstance();
        vm.prank(admin);
        vm.expectRevert(ProtocolRegistry.UnauthorizedRegistrar.selector);
        registry.registerInstance(address(formerOwnerInstance), seller, address(0), KIND, 1);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../support/TestBase.sol";

contract RegistryFuzzInstance { }

contract ProtocolRegistryFuzzTest is ProtocolTestBase {
    ProtocolRegistry internal registry;

    function setUp() public {
        registry = new ProtocolRegistry(admin);
    }

    function testFuzz_ValidVersionsArePersisted(uint64 version) public {
        vm.assume(version > 0);
        RegistryFuzzInstance instance = new RegistryFuzzInstance();
        bytes32 kind = keccak256(abi.encode("KIND", version));
        vm.prank(admin);
        registry.registerInstance(address(instance), seller, address(0), kind, version);
        assertEq(registry.getRecord(address(instance)).version, version);
        assertEq(registry.byKindCount(kind), 1);
    }
}

contract ProtocolRegistryFuzzAdditionalTest is ProtocolTestBase {
    ProtocolRegistry internal registry;

    function setUp() public {
        registry = new ProtocolRegistry(admin);
    }

    function testFuzz_RegisterPreservesCreatorAndKind(bytes32 kind, uint64 version) public {
        vm.assume(version > 0);
        RegistryFuzzAdditionalInstance instance = new RegistryFuzzAdditionalInstance();
        vm.prank(admin);
        registry.registerInstance(address(instance), buyer, address(0), kind, version);
        IRegistry.Record memory record = registry.getRecord(address(instance));
        assertEq(record.creator, buyer);
        assertEq(record.kind, kind);
        assertEq(record.version, version);
        assertTrue(record.active);
    }
}

contract RegistryFuzzAdditionalInstance { }

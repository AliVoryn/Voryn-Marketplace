// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../support/TestBase.sol";
import "forge-std/StdInvariant.sol";

contract RegistryInvariantInstance { }

contract ProtocolRegistryInvariantHandler is Test {
    ProtocolRegistry internal immutable registry;
    address internal immutable creatorA;
    address internal immutable creatorB;
    uint256 public registeredCount;
    uint256 public creatorACount;
    uint256 public creatorBCount;
    uint256[4] public kindCounts;
    bytes32 internal constant KIND_A = keccak256("REGISTRY_KIND_A");
    bytes32 internal constant KIND_B = keccak256("REGISTRY_KIND_B");
    bytes32 internal constant KIND_C = keccak256("REGISTRY_KIND_C");
    bytes32 internal constant KIND_D = keccak256("REGISTRY_KIND_D");

    constructor(ProtocolRegistry registry_, address creatorA_, address creatorB_) {
        registry = registry_;
        creatorA = creatorA_;
        creatorB = creatorB_;
    }

    function register(uint8 selector, uint64 version) external {
        if (version == 0) version = 1;
        address creator = (selector & 1) == 0 ? creatorA : creatorB;
        bytes32 kind = _kind(selector >> 1);
        RegistryInvariantInstance instance = new RegistryInvariantInstance();
        registry.registerInstance(address(instance), creator, address(0), kind, version);
        ++registeredCount;
        if (creator == creatorA) {
            ++creatorACount;
        } else {
            ++creatorBCount;
        }
        kindCounts[(selector >> 1) & 3]++;
    }

    function _kind(uint8 index) private pure returns (bytes32) {
        uint8 normalized = index & 3;
        if (normalized == 0) return KIND_A;
        if (normalized == 1) return KIND_B;
        if (normalized == 2) return KIND_C;
        return KIND_D;
    }
}

contract ProtocolRegistryInvariantTest is StdInvariant, ProtocolTestBase {
    ProtocolRegistry internal registry;
    ProtocolRegistryInvariantHandler internal handler;
    address internal constant CREATOR_A = address(0xA11CE);
    address internal constant CREATOR_B = address(0xB0B);
    bytes32 internal constant KIND_A = keccak256("REGISTRY_KIND_A");
    bytes32 internal constant KIND_B = keccak256("REGISTRY_KIND_B");
    bytes32 internal constant KIND_C = keccak256("REGISTRY_KIND_C");
    bytes32 internal constant KIND_D = keccak256("REGISTRY_KIND_D");

    function setUp() public {
        registry = new ProtocolRegistry(admin);
        handler = new ProtocolRegistryInvariantHandler(registry, CREATOR_A, CREATOR_B);
        vm.prank(admin);
        registry.setRegistrar(address(handler), true);
        targetContract(address(handler));
    }

    function invariant_RegistryIndexesRemainConsistent() public view {
        uint256 count = registry.allCount();
        assertEq(count, handler.registeredCount());
        assertEq(registry.byCreatorCount(CREATOR_A), handler.creatorACount());
        assertEq(registry.byCreatorCount(CREATOR_B), handler.creatorBCount());
        assertEq(registry.byKindCount(KIND_A), handler.kindCounts(0));
        assertEq(registry.byKindCount(KIND_B), handler.kindCounts(1));
        assertEq(registry.byKindCount(KIND_C), handler.kindCounts(2));
        assertEq(registry.byKindCount(KIND_D), handler.kindCounts(3));

        for (uint256 i; i < count; ++i) {
            address instance = registry.allAt(i);
            IRegistry.Record memory record = registry.getRecord(instance);
            assertEq(record.instance, instance);
            assertTrue(registry.isRegistered(instance));
            assertTrue(record.active);
        }
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../support/TestBase.sol";
import "forge-std/StdInvariant.sol";

contract FactoryInvariantHandler is Test {
    ProtocolFactory internal immutable factory;
    uint256 public created;

    constructor(ProtocolFactory factory_) {
        factory = factory_;
    }

    function createNFT(uint8 selector) external {
        if (created >= 16) return;
        address admin = (selector & 1) == 0 ? address(0xA11CE) : address(0xB0B);
        factory.createCustomNFT("Invariant", "INV", 64, admin);
        ++created;
    }
}

contract ProtocolFactoryInvariantTest is StdInvariant, ProtocolTestBase {
    ProtocolFactory internal factory;
    FactoryInvariantHandler internal handler;

    function setUp() public {
        vm.prank(admin);
        factory = new ProtocolFactory(admin);
        handler = new FactoryInvariantHandler(factory);
        targetContract(address(handler));
    }

    function invariant_FactoryCreatorIndexMatchesRegistry() public view {
        uint256 count = handler.created();
        assertEq(factory.creatorInstanceCount(address(handler)), count);
        ProtocolRegistry registry = factory.registry();
        assertEq(registry.byCreatorCount(address(handler)), count);
        for (uint256 i; i < count; ++i) {
            address instance = factory.creatorInstanceAt(address(handler), i);
            assertTrue(registry.isRegistered(instance));
            IRegistry.Record memory record = registry.getRecord(instance);
            assertEq(record.instance, instance);
            assertEq(record.creator, address(handler));
            assertEq(record.kind, factory.KIND_NFT());
            assertTrue(record.active);
        }
    }
}

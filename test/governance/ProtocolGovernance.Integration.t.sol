// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../support/TestBase.sol";
import "../../src/governance/ProtocolGovernance.sol";

contract ProtocolGovernanceIntegrationTest is ProtocolTestBase {
    uint256 internal constant DELAY = 2 days;

    ProtocolTimelock internal timelock;
    ProtocolFactory internal factory;
    address internal deployer = makeAddr("deployer");
    address internal proposer = makeAddr("proposer");
    address internal executor = makeAddr("executor");

    function setUp() public {
        address[] memory proposers = new address[](1);
        proposers[0] = proposer;
        address[] memory executors = new address[](1);
        executors[0] = executor;
        timelock = new ProtocolTimelock(DELAY, proposers, executors, address(0));
        vm.prank(deployer);
        factory = new ProtocolFactory(deployer);
    }

    function _schedule(address target, bytes memory data, bytes32 salt) internal {
        vm.prank(proposer);
        timelock.schedule(target, 0, data, bytes32(0), salt, DELAY);
    }

    function _execute(address target, bytes memory data, bytes32 salt) internal {
        vm.warp(block.timestamp + DELAY);
        vm.prank(executor);
        timelock.execute(target, 0, data, bytes32(0), salt);
    }

    function _deploySuite() internal returns (address treasuryAddr, address pmAddr, address marketplaceAddr) {
        vm.startPrank(deployer);
        (treasuryAddr, pmAddr, marketplaceAddr,,,) = factory.createProtocolSuite(address(timelock), feeRecipient);
        factory.finalizeProtocolSuiteControllers(treasuryAddr, pmAddr);
        vm.stopPrank();
    }

    function test_TimelockAcceptsSuiteOwnershipThroughScheduledBatch() public {
        (address treasuryAddr, address pmAddr,) = _deploySuite();
        assertEq(Ownable2Step(treasuryAddr).owner(), address(factory));
        assertEq(Ownable2Step(treasuryAddr).pendingOwner(), address(timelock));

        address[] memory targets = new address[](2);
        targets[0] = treasuryAddr;
        targets[1] = pmAddr;
        uint256[] memory values = new uint256[](2);
        bytes[] memory payloads = new bytes[](2);
        payloads[0] = abi.encodeWithSignature("acceptOwnership()");
        payloads[1] = abi.encodeWithSignature("acceptOwnership()");
        bytes32 salt = keccak256("accept-suite");

        vm.prank(proposer);
        timelock.scheduleBatch(targets, values, payloads, bytes32(0), salt, DELAY);

        vm.prank(executor);
        vm.expectRevert();
        timelock.executeBatch(targets, values, payloads, bytes32(0), salt);

        vm.warp(block.timestamp + DELAY);
        vm.prank(executor);
        timelock.executeBatch(targets, values, payloads, bytes32(0), salt);

        assertEq(Ownable2Step(treasuryAddr).owner(), address(timelock));
        assertEq(Ownable2Step(treasuryAddr).pendingOwner(), address(0));
        assertEq(Ownable2Step(pmAddr).owner(), address(timelock));
        assertEq(Ownable2Step(pmAddr).pendingOwner(), address(0));
    }

    function test_FinalizationMustPrecedeOwnershipAcceptance() public {
        (address treasuryAddr, address pmAddr,) = _deploySuite();
        vm.prank(address(timelock));
        Ownable2Step(treasuryAddr).acceptOwnership();
        vm.prank(address(timelock));
        Ownable2Step(pmAddr).acceptOwnership();
        vm.prank(deployer);
        vm.expectRevert(ProtocolFactory.UnauthorizedTreasuryController.selector);
        factory.finalizeProtocolSuiteControllers(treasuryAddr, pmAddr);
    }

    function test_TreasuryConfigurationChangesOnlyThroughTimelock() public {
        (address treasuryAddr,,) = _deploySuite();
        vm.prank(address(timelock));
        Ownable2Step(treasuryAddr).acceptOwnership();
        address newRecipient = makeAddr("governedFeeRecipient");
        bytes memory data = abi.encodeCall(Treasury.setFeeRecipient, (newRecipient));

        vm.prank(deployer);
        vm.expectRevert();
        Treasury(payable(treasuryAddr)).setFeeRecipient(newRecipient);

        _schedule(treasuryAddr, data, keccak256("fee-recipient"));
        assertEq(Treasury(payable(treasuryAddr)).feeRecipient(), feeRecipient);
        _execute(treasuryAddr, data, keccak256("fee-recipient"));
        assertEq(Treasury(payable(treasuryAddr)).feeRecipient(), newRecipient);
    }

    function test_MarketplaceAdminRoleIsHeldByTimelock() public {
        (,, address marketplaceAddr) = _deploySuite();
        Marketplace marketplace = Marketplace(marketplaceAddr);
        assertTrue(marketplace.hasRole(marketplace.DEFAULT_ADMIN_ROLE(), address(timelock)));
        assertFalse(marketplace.hasRole(marketplace.DEFAULT_ADMIN_ROLE(), deployer));

        vm.prank(deployer);
        vm.expectRevert();
        marketplace.setProtocolFee(500);

        bytes memory data = abi.encodeCall(Marketplace.setProtocolFee, (uint16(500)));
        _schedule(marketplaceAddr, data, keccak256("marketplace-fee"));
        _execute(marketplaceAddr, data, keccak256("marketplace-fee"));
        assertEq(marketplace.protocolFeeBps(), 500);
    }

    function test_ProposerCanCancelScheduledOperation() public {
        (address treasuryAddr,,) = _deploySuite();
        vm.prank(address(timelock));
        Ownable2Step(treasuryAddr).acceptOwnership();
        bytes memory data = abi.encodeCall(Treasury.setFeeRecipient, (attacker));
        bytes32 salt = keccak256("malicious-recipient");
        _schedule(treasuryAddr, data, salt);
        bytes32 operationId = timelock.hashOperation(treasuryAddr, 0, data, bytes32(0), salt);
        assertTrue(timelock.isOperationPending(operationId));

        vm.prank(proposer);
        timelock.cancel(operationId);
        assertFalse(timelock.isOperation(operationId));

        vm.warp(block.timestamp + DELAY);
        vm.prank(executor);
        vm.expectRevert();
        timelock.execute(treasuryAddr, 0, data, bytes32(0), salt);
        assertEq(Treasury(payable(treasuryAddr)).feeRecipient(), feeRecipient);
    }

    function test_FactoryAndRegistryOwnershipMoveToTimelockWithoutLosingRegistrarRights() public {
        vm.startPrank(deployer);
        factory.transferRegistryOwnership(address(timelock));
        factory.transferOwnership(address(timelock));
        vm.stopPrank();

        ProtocolRegistry registry = factory.registry();
        address[] memory targets = new address[](2);
        targets[0] = address(factory);
        targets[1] = address(registry);
        uint256[] memory values = new uint256[](2);
        bytes[] memory payloads = new bytes[](2);
        payloads[0] = abi.encodeWithSignature("acceptOwnership()");
        payloads[1] = abi.encodeWithSignature("acceptOwnership()");
        bytes32 salt = keccak256("accept-factory-registry");
        vm.prank(proposer);
        timelock.scheduleBatch(targets, values, payloads, bytes32(0), salt, DELAY);
        vm.warp(block.timestamp + DELAY);
        vm.prank(executor);
        timelock.executeBatch(targets, values, payloads, bytes32(0), salt);

        assertEq(factory.owner(), address(timelock));
        assertEq(registry.owner(), address(timelock));
        assertTrue(registry.registrar(address(factory)));

        vm.prank(seller);
        address nftAddr = factory.createCustomNFT("Governed", "GOV", 10, seller);
        assertTrue(registry.isRegistered(nftAddr));
    }
}

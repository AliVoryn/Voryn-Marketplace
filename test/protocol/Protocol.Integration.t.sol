// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../support/TestBase.sol";

contract ProtocolIntegrationTest is ProtocolTestBase {
    ProtocolFactory internal factory;

    function setUp() public {
        _setUpCore();
        factory = new ProtocolFactory(admin);
    }

    function test_FullSuite_ComposesMarketplaceTreasuryPaymentManagerAndRegistry() public {
        vm.prank(admin);
        (address treasuryAddr, address paymentManagerAddr, address marketplaceAddr,,, address dutchAuctionAddr) =
            factory.createProtocolSuite(admin, feeRecipient);

        Marketplace marketplace = Marketplace(marketplaceAddr);
        Treasury suiteTreasury = Treasury(payable(treasuryAddr));
        PaymentManager suitePaymentManager = PaymentManager(payable(paymentManagerAddr));
        ProtocolRegistry suiteRegistry = factory.registry();

        assertEq(marketplace.treasury(), treasuryAddr);
        assertEq(marketplace.paymentManager(), paymentManagerAddr);
        assertTrue(suiteTreasury.authorizedPayer(marketplaceAddr));
        assertTrue(suiteTreasury.authorizedPayer(dutchAuctionAddr));
        assertTrue(suitePaymentManager.authorizedCreditor(marketplaceAddr));
        assertTrue(suiteRegistry.isRegistered(marketplaceAddr));
        assertTrue(suiteRegistry.isRegistered(dutchAuctionAddr));
    }

    function test_FullSuite_AllowsFactoryRaffleCreationBeforeControllerFinalization() public {
        MockVRFCoordinatorV2Plus coordinator = _deployMockCoordinator();
        vm.prank(admin);
        (address treasuryAddr,,,,,) = factory.createProtocolSuite(admin, feeRecipient);

        vm.prank(admin);
        address raffle = factory.createRaffleInstance(
            admin, treasuryAddr, 250, address(coordinator), 1, bytes32(uint256(1)), 200_000, 3, false
        );

        assertTrue(Treasury(payable(treasuryAddr)).authorizedPayer(raffle));
        assertTrue(factory.registry().isRegistered(raffle));
    }

    function test_FinalizedSuiteRejectsFurtherFactoryCreatedPayers() public {
        vm.prank(admin);
        (address treasuryAddr, address paymentManagerAddr,,,,) = factory.createProtocolSuite(admin, feeRecipient);
        vm.prank(admin);
        factory.finalizeProtocolSuiteControllers(treasuryAddr, paymentManagerAddr);
        vm.prank(admin);
        address controlledTreasury = factory.createTreasury(feeRecipient);

        vm.startPrank(admin);
        vm.expectRevert(ProtocolFactory.UnauthorizedTreasuryController.selector);
        factory.createAuctionInstance(treasuryAddr);
        vm.expectRevert(ProtocolFactory.UnauthorizedTreasuryController.selector);
        factory.createDutchAuctionInstance(admin, treasuryAddr, FEE_BPS);
        vm.expectRevert(ProtocolFactory.UnauthorizedTreasuryController.selector);
        factory.createStaking(treasuryAddr);
        vm.expectRevert(ProtocolFactory.UnauthorizedPaymentManagerController.selector);
        factory.createMarketplace(admin, controlledTreasury, paymentManagerAddr);
        vm.stopPrank();
    }

    function test_FinalizedSuiteStillAcceptsPayersFromItsOwner() public {
        vm.prank(admin);
        (address treasuryAddr, address paymentManagerAddr,,,,) = factory.createProtocolSuite(admin, feeRecipient);
        vm.prank(admin);
        factory.finalizeProtocolSuiteControllers(treasuryAddr, paymentManagerAddr);
        vm.prank(admin);
        Ownable2Step(treasuryAddr).acceptOwnership();
        address newPayer = makeAddr("governancePayer");
        vm.prank(admin);
        Treasury(payable(treasuryAddr)).setAuthorizedPayer(newPayer, true);
        assertTrue(Treasury(payable(treasuryAddr)).authorizedPayer(newPayer));
        vm.prank(newPayer);
        vm.expectRevert(ITreasury.Unauthorized.selector);
        Treasury(payable(treasuryAddr)).setAuthorizedPayer(attacker, true);
    }
}

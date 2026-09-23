// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import "../support/TestBase.sol";

contract FactoryIntegrationTest is ProtocolTestBase {
    ProtocolFactory internal factory;

    function setUp() public {
        _setUpCore();
        vm.prank(admin);
        factory = new ProtocolFactory(admin);
    }

    function test_TreasuryOwnershipRemainsPendingUntilAdminAccepts() public {
        vm.prank(seller);
        address treasuryAddr = factory.createTreasury(feeRecipient);
        assertEq(
            Ownable2Step(treasuryAddr).owner(),
            address(factory),
            "factory must still be owner() until acceptOwnership()"
        );
        assertEq(Ownable2Step(treasuryAddr).pendingOwner(), seller);
    }

    function test_MarketplaceCreationWorksWithFactoryController() public {
        vm.startPrank(seller);
        address treasuryAddr = factory.createTreasury(feeRecipient);
        address pmAddr = factory.createPaymentManager();
        address marketplaceAddr = factory.createMarketplace(seller, treasuryAddr, pmAddr);
        vm.stopPrank();
        assertTrue(marketplaceAddr != address(0));
    }

    function test_MarketplaceCreationRemainsAvailableAfterOwnershipHandoff() public {
        vm.startPrank(seller);
        address treasuryAddr = factory.createTreasury(feeRecipient);
        address pmAddr = factory.createPaymentManager();
        vm.stopPrank();
        vm.prank(seller);
        Ownable2Step(treasuryAddr).acceptOwnership();
        vm.prank(seller);
        Ownable2Step(pmAddr).acceptOwnership();
        vm.prank(seller);
        address marketplaceAddr = factory.createMarketplace(seller, treasuryAddr, pmAddr);
        assertTrue(marketplaceAddr != address(0));
    }

    function test_CreateTreasury_RegistersInRegistry() public {
        vm.prank(seller);
        address treasuryAddr = factory.createTreasury(feeRecipient);
        ProtocolRegistry registry = factory.registry();
        assertTrue(registry.isRegistered(treasuryAddr));
    }

    function test_FactoryRejectsZeroConfigurationInputs() public {
        vm.prank(seller);
        vm.expectRevert(ProtocolFactory.ZeroAddress.selector);
        factory.createTreasury(address(0));
        vm.prank(seller);
        vm.expectRevert(ProtocolFactory.ZeroAddress.selector);
        factory.createMarketplace(address(0), address(1), address(2));
        vm.prank(seller);
        vm.expectRevert(ProtocolFactory.ZeroAddress.selector);
        factory.createCustomNFT("X", "X", 1, address(0));
        vm.prank(seller);
        vm.expectRevert(ProtocolFactory.ZeroAddress.selector);
        factory.createAuctionInstance(address(0));
        vm.prank(seller);
        vm.expectRevert(ProtocolFactory.ZeroAddress.selector);
        factory.createDutchAuctionInstance(address(0), address(1), FEE_BPS);
        vm.prank(seller);
        vm.expectRevert(ProtocolFactory.ZeroAddress.selector);
        factory.createStaking(address(0));
    }

    function test_DeterministicNFTPredictionAndSaltReuse() public {
        bytes32 salt = keccak256("salt");
        address predicted = factory.predictCustomNFTAddress(seller, "Collection", "COL", 100, seller, salt);
        vm.prank(seller);
        address created = factory.createCustomNFTDeterministic("Collection", "COL", 100, seller, salt);
        assertEq(created, predicted);
        vm.prank(seller);
        vm.expectRevert(ProtocolFactory.SaltAlreadyUsed.selector);
        factory.createCustomNFTDeterministic("Collection", "COL", 100, seller, salt);
    }

    function test_FactoryCanBeRevokedAsTreasuryController() public {
        vm.prank(seller);
        address treasuryAddr = factory.createTreasury(feeRecipient);
        vm.prank(seller);
        Ownable2Step(treasuryAddr).acceptOwnership();
        vm.prank(seller);
        Treasury(payable(treasuryAddr)).setFactoryController(address(0));
        vm.prank(seller);
        vm.expectRevert(ProtocolFactory.UnauthorizedTreasuryController.selector);
        factory.createAuctionInstance(treasuryAddr);
    }

    function test_FactoryCanBeRevokedAsPaymentManagerController() public {
        vm.prank(seller);
        address treasuryAddr = factory.createTreasury(feeRecipient);
        vm.prank(seller);
        address paymentManagerAddr = factory.createPaymentManager();
        vm.prank(seller);
        Ownable2Step(paymentManagerAddr).acceptOwnership();
        vm.prank(seller);
        PaymentManager(payable(paymentManagerAddr)).setFactoryController(address(0));
        vm.prank(seller);
        vm.expectRevert(ProtocolFactory.UnauthorizedPaymentManagerController.selector);
        factory.createMarketplace(seller, treasuryAddr, paymentManagerAddr);
    }

    function test_CreateRaffleInstance_AuthorizesItselfAsTreasuryPayer() public {
        vm.startPrank(seller);
        address treasuryAddr = factory.createTreasury(feeRecipient);
        MockVRFCoordinatorV2Plus coordinator = new MockVRFCoordinatorV2Plus();
        address raffleAddr = factory.createRaffleInstance(
            seller, treasuryAddr, FEE_BPS, address(coordinator), 1, bytes32(uint256(1)), 200_000, 3, false
        );
        vm.stopPrank();
        assertTrue(
            Treasury(payable(treasuryAddr)).authorizedPayer(raffleAddr),
            "factory must authorize the new Raffle instance as a Treasury payer"
        );
    }

    function test_CreateProtocolSuite_WiresAllFiveComponents() public {
        vm.prank(admin);
        (
            address treasuryAddr,
            address pmAddr,
            address marketplaceAddr,
            address auctionAddr,
            address stakingAddr,
            address dutchAuctionAddr
        ) = factory.createProtocolSuite(admin, feeRecipient);
        assertTrue(treasuryAddr != address(0));
        assertTrue(pmAddr != address(0));
        assertTrue(marketplaceAddr != address(0));
        assertTrue(auctionAddr != address(0));
        assertTrue(stakingAddr != address(0));
        assertTrue(dutchAuctionAddr != address(0));
        assertEq(Ownable2Step(treasuryAddr).pendingOwner(), admin);
    }

    function test_FinalizeProtocolSuiteControllersRemovesFactoryChildAuthority() public {
        vm.prank(admin);
        (address treasuryAddr, address pmAddr,,,,) = factory.createProtocolSuite(admin, feeRecipient);
        assertEq(Treasury(payable(treasuryAddr)).factoryController(), address(factory));
        assertEq(PaymentManager(payable(pmAddr)).factoryController(), address(factory));

        vm.prank(admin);
        factory.finalizeProtocolSuiteControllers(treasuryAddr, pmAddr);

        assertEq(Treasury(payable(treasuryAddr)).factoryController(), address(0));
        assertEq(PaymentManager(payable(pmAddr)).factoryController(), address(0));
    }

    function test_RegistryKeepsFactoryAsRegistrarAfterOwnershipHandoff() public {
        vm.prank(admin);
        factory.transferRegistryOwnership(seller);

        ProtocolRegistry registry = factory.registry();
        vm.prank(seller);
        registry.acceptOwnership();

        vm.prank(seller);
        address nftAddr = factory.createCustomNFT("PostHandoff", "PH", 10, seller);
        assertTrue(registry.isRegistered(nftAddr));
    }

    function test_CreateBlindAuctionInstance_RevertsWhenBeneficiaryDoesNotOwnToken() public {
        vm.prank(admin);
        address treasuryAddr = factory.createTreasury(feeRecipient);
        uint256 tokenId_ = _mint(nft, seller2);
        vm.prank(seller);
        vm.expectRevert(ProtocolFactory.NotSeller.selector);
        factory.createBlindAuctionInstance(
            seller, payable(seller), address(nft), tokenId_, treasuryAddr, FEE_BPS, 1 days, 1 days, 0.01 ether
        );
    }

    function test_CreateAuctionInstance_WorksAfterTreasuryOwnershipHandoff() public {
        vm.prank(seller);
        address treasuryAddr = factory.createTreasury(feeRecipient);
        vm.prank(seller);
        Ownable2Step(treasuryAddr).acceptOwnership();
        vm.prank(seller);
        address auctionAddr = factory.createAuctionInstance(treasuryAddr);
        assertTrue(auctionAddr != address(0));
    }

    function test_CreateStaking_WorksAfterTreasuryOwnershipHandoff() public {
        vm.prank(seller);
        address treasuryAddr = factory.createTreasury(feeRecipient);
        vm.prank(seller);
        Ownable2Step(treasuryAddr).acceptOwnership();
        vm.prank(seller);
        address stakingAddr = factory.createStaking(treasuryAddr);
        assertTrue(stakingAddr != address(0));
    }

    function test_CreateDutchAuctionInstance_WorksAfterTreasuryOwnershipHandoff() public {
        vm.prank(seller);
        address treasuryAddr = factory.createTreasury(feeRecipient);
        vm.prank(seller);
        Ownable2Step(treasuryAddr).acceptOwnership();
        vm.prank(seller);
        address auctionAddr = factory.createDutchAuctionInstance(seller, treasuryAddr, FEE_BPS);
        assertTrue(auctionAddr != address(0));
    }

    function test_CreateRaffleInstance_WorksAfterTreasuryOwnershipHandoff() public {
        vm.prank(seller);
        address treasuryAddr = factory.createTreasury(feeRecipient);
        vm.prank(seller);
        Ownable2Step(treasuryAddr).acceptOwnership();
        MockVRFCoordinatorV2Plus coordinator = new MockVRFCoordinatorV2Plus();
        vm.prank(seller);
        address raffleAddr = factory.createRaffleInstance(
            seller, treasuryAddr, FEE_BPS, address(coordinator), 1, bytes32(uint256(1)), 200_000, 3, false
        );
        assertTrue(raffleAddr != address(0));
    }

    function test_TransferRegistryOwnership_RevertsForZeroAddressAndSucceeds() public {
        vm.prank(admin);
        vm.expectRevert(ProtocolFactory.ZeroAddress.selector);
        factory.transferRegistryOwnership(address(0));

        vm.prank(admin);
        factory.transferRegistryOwnership(seller);
        assertEq(factory.registry().pendingOwner(), seller);
    }

    function test_CreateMarketplace_WorksAfterPaymentManagerOwnershipHandoff() public {
        vm.startPrank(seller);
        address treasuryAddr = factory.createTreasury(feeRecipient);
        address pmAddr = factory.createPaymentManager();
        vm.stopPrank();
        vm.prank(seller);
        Ownable2Step(pmAddr).acceptOwnership();
        vm.prank(seller);
        address marketplaceAddr = factory.createMarketplace(seller, treasuryAddr, pmAddr);
        assertTrue(marketplaceAddr != address(0));
    }

    function test_CreatorInstanceTracking() public {
        vm.prank(seller);
        address treasuryAddr = factory.createTreasury(feeRecipient);
        assertEq(factory.creatorInstanceCount(seller), 1);
        assertEq(factory.creatorInstanceAt(seller, 0), treasuryAddr);
    }

    function test_CreateIndividualInstances_RegistersAndWires() public {
        vm.startPrank(seller);
        address treasuryAddr = factory.createTreasury(feeRecipient);
        address paymentManagerAddr = factory.createPaymentManager();
        address nftAddr = factory.createCustomNFT("Collection", "COL", 100, seller);
        address auctionAddr = factory.createAuctionInstance(treasuryAddr);
        address dutchAddr = factory.createDutchAuctionInstance(seller, treasuryAddr, FEE_BPS);
        address stakingAddr = factory.createStaking(treasuryAddr);
        vm.stopPrank();

        assertTrue(factory.registry().isRegistered(paymentManagerAddr));
        assertTrue(factory.registry().isRegistered(nftAddr));
        assertTrue(factory.registry().isRegistered(auctionAddr));
        assertTrue(factory.registry().isRegistered(dutchAddr));
        assertTrue(factory.registry().isRegistered(stakingAddr));
        assertTrue(Treasury(payable(treasuryAddr)).authorizedPayer(auctionAddr));
        assertTrue(Treasury(payable(treasuryAddr)).authorizedPayer(dutchAddr));
        assertTrue(Treasury(payable(treasuryAddr)).authorizedPayer(stakingAddr));
    }

    function test_ZeroAddressGuardsCoverFactoryCreationPaths() public {
        vm.prank(seller);
        vm.expectRevert(ProtocolFactory.ZeroAddress.selector);
        factory.createCustomNFTDeterministic("X", "X", 1, address(0), bytes32(uint256(1)));

        vm.prank(seller);
        vm.expectRevert(ProtocolFactory.ZeroAddress.selector);
        factory.createBlindAuctionInstance(
            address(0), payable(seller), address(nft), 1, address(treasury), FEE_BPS, 1 days, 1 days, 1
        );
        vm.prank(seller);
        vm.expectRevert(ProtocolFactory.ZeroAddress.selector);
        factory.createBlindAuctionInstance(
            seller, payable(address(0)), address(nft), 1, address(treasury), FEE_BPS, 1 days, 1 days, 1
        );
        vm.prank(seller);
        vm.expectRevert(ProtocolFactory.ZeroAddress.selector);
        factory.createBlindAuctionInstance(
            seller, payable(seller), address(0), 1, address(treasury), FEE_BPS, 1 days, 1 days, 1
        );
        vm.prank(seller);
        vm.expectRevert(ProtocolFactory.ZeroAddress.selector);
        factory.createBlindAuctionInstance(
            seller, payable(seller), address(nft), 1, address(0), FEE_BPS, 1 days, 1 days, 1
        );

        vm.prank(seller);
        vm.expectRevert(ProtocolFactory.ZeroAddress.selector);
        factory.createRaffleInstance(address(0), address(treasury), FEE_BPS, address(1), 1, bytes32(0), 1, 1, false);
        vm.prank(seller);
        vm.expectRevert(ProtocolFactory.ZeroAddress.selector);
        factory.createRaffleInstance(seller, address(0), FEE_BPS, address(1), 1, bytes32(0), 1, 1, false);
        vm.prank(seller);
        vm.expectRevert(ProtocolFactory.ZeroAddress.selector);
        factory.createProtocolSuite(address(0), feeRecipient);
        vm.prank(seller);
        vm.expectRevert(ProtocolFactory.ZeroAddress.selector);
        factory.createProtocolSuite(seller, address(0));
    }
}

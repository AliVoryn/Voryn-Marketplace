// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../support/TestBase.sol";

contract ProtocolFactorySecurityTest is ProtocolTestBase {
    ProtocolFactory internal factory;

    function setUp() public {
        vm.prank(admin);
        factory = new ProtocolFactory(admin);
    }

    function test_NonOwnerCannotFinalizeProtocolSuiteControllers() public {
        vm.prank(attacker);
        vm.expectRevert();
        factory.finalizeProtocolSuiteControllers(address(1), address(2));
    }

    function test_NonOwnerCannotTransferRegistryOwnership() public {
        vm.prank(attacker);
        vm.expectRevert();
        factory.transferRegistryOwnership(attacker);
    }

    function test_SaltCannotBeReusedBySameCreator() public {
        bytes32 salt = keccak256("SALT");
        vm.startPrank(seller);
        factory.createCustomNFTDeterministic("X", "X", 10, seller, salt);
        vm.expectRevert(ProtocolFactory.SaltAlreadyUsed.selector);
        factory.createCustomNFTDeterministic("X", "X", 10, seller, salt);
        vm.stopPrank();
    }

    function test_CreateMarketplaceRejectsPaymentManagerWithoutFactoryController() public {
        Treasury standaloneTreasury = new Treasury(admin, feeRecipient, address(factory));
        PaymentManager standaloneManager = new PaymentManager(admin, address(0));
        vm.prank(seller);
        vm.expectRevert(ProtocolFactory.UnauthorizedPaymentManagerController.selector);
        factory.createMarketplace(seller, address(standaloneTreasury), address(standaloneManager));
    }

    function test_CreateBlindAuctionRejectsNonContractAsset() public {
        vm.prank(seller);
        vm.expectRevert(ProtocolFactory.InvalidContract.selector);
        factory.createBlindAuctionInstance(
            seller, payable(seller), address(0x1234), 1, address(0x5678), FEE_BPS, 1 days, 1 days, 1 ether
        );
    }
}

contract ProtocolFactorySecurityAdditionalTest is ProtocolTestBase {
    ProtocolFactory internal factory;

    function setUp() public {
        vm.prank(admin);
        factory = new ProtocolFactory(admin);
    }

    function test_CreateCustomNFTDeterministic_IsNamespacedByCreator() public {
        bytes32 salt = keccak256("shared-salt");
        vm.prank(seller);
        address sellerInstance = factory.createCustomNFTDeterministic("X", "X", 10, seller, salt);
        vm.prank(buyer);
        address buyerInstance = factory.createCustomNFTDeterministic("X", "X", 10, buyer, salt);
        assertTrue(sellerInstance != buyerInstance);
        assertEq(factory.usedSalts(seller, salt), true);
        assertEq(factory.usedSalts(buyer, salt), true);
    }

    function test_CreateDutchAuctionRejectsFeeAboveProtocolCap() public {
        vm.prank(admin);
        address treasuryAddr = factory.createTreasury(feeRecipient);
        vm.prank(admin);
        vm.expectRevert(IDutchAuction.FeeTooHigh.selector);
        factory.createDutchAuctionInstance(admin, treasuryAddr, 1001);
    }

    function test_CreateRaffleRejectsInvalidCoordinator() public {
        vm.prank(admin);
        address treasuryAddr = factory.createTreasury(feeRecipient);
        vm.prank(admin);
        vm.expectRevert(IRaffle.InvalidVRFCoordinator.selector);
        factory.createRaffleInstance(admin, treasuryAddr, FEE_BPS, attacker, 1, bytes32(uint256(1)), 200_000, 3, false);
    }

    function test_CreateStakingRequiresFactoryControlledTreasury() public {
        Treasury standalone = new Treasury(admin, feeRecipient, address(0));
        vm.prank(admin);
        vm.expectRevert(ProtocolFactory.UnauthorizedTreasuryController.selector);
        factory.createStaking(address(standalone));
    }

    function test_FinalizeControllersRejectsAlreadyRevokedTreasuryController() public {
        vm.prank(admin);
        (address treasuryAddr, address paymentManagerAddr,,,,) = factory.createProtocolSuite(admin, feeRecipient);
        vm.prank(admin);
        factory.finalizeProtocolSuiteControllers(treasuryAddr, paymentManagerAddr);
        vm.prank(admin);
        vm.expectRevert(ProtocolFactory.UnauthorizedTreasuryController.selector);
        factory.finalizeProtocolSuiteControllers(treasuryAddr, paymentManagerAddr);
    }
}

contract ProtocolFactoryTreasuryAuthorityTest is ProtocolTestBase {
    ProtocolFactory internal factory;

    function setUp() public {
        _setUpCore();
        vm.prank(admin);
        factory = new ProtocolFactory(admin);
    }

    function test_CreateStakingRejectsCallerWithoutTreasuryAuthority() public {
        vm.prank(seller);
        address treasuryAddr = factory.createTreasury(feeRecipient);
        vm.prank(attacker);
        vm.expectRevert(ProtocolFactory.NotTreasuryAuthority.selector);
        factory.createStaking(treasuryAddr);
    }

    function test_CreateMarketplaceRejectsCallerWithoutTreasuryAuthority() public {
        vm.startPrank(seller);
        address treasuryAddr = factory.createTreasury(feeRecipient);
        address pmAddr = factory.createPaymentManager();
        vm.stopPrank();
        vm.prank(attacker);
        vm.expectRevert(ProtocolFactory.NotTreasuryAuthority.selector);
        factory.createMarketplace(attacker, treasuryAddr, pmAddr);
    }

    function test_PendingOwnerAndOwnerMayCreateTreasuryBoundInstances() public {
        vm.startPrank(seller);
        address treasuryAddr = factory.createTreasury(feeRecipient);
        address pmAddr = factory.createPaymentManager();
        address firstStaking = factory.createStaking(treasuryAddr);
        Ownable2Step(treasuryAddr).acceptOwnership();
        address secondStaking = factory.createStaking(treasuryAddr);
        address marketplaceAddr = factory.createMarketplace(seller, treasuryAddr, pmAddr);
        vm.stopPrank();
        assertTrue(firstStaking != secondStaking);
        assertTrue(Treasury(payable(treasuryAddr)).authorizedPayer(firstStaking));
        assertTrue(Treasury(payable(treasuryAddr)).authorizedPayer(secondStaking));
        assertTrue(Treasury(payable(treasuryAddr)).authorizedPayer(marketplaceAddr));
    }

    function test_FactoryOwnerHasNoImplicitTreasuryAuthority() public {
        vm.prank(seller);
        address treasuryAddr = factory.createTreasury(feeRecipient);
        vm.prank(admin);
        vm.expectRevert(ProtocolFactory.NotTreasuryAuthority.selector);
        factory.createStaking(treasuryAddr);
    }

    function test_FinalizeRejectsZeroAddresses() public {
        vm.prank(admin);
        vm.expectRevert(ProtocolFactory.ZeroAddress.selector);
        factory.finalizeProtocolSuiteControllers(address(0), address(1));
        vm.prank(admin);
        vm.expectRevert(ProtocolFactory.ZeroAddress.selector);
        factory.finalizeProtocolSuiteControllers(address(1), address(0));
    }

    function test_FinalizeRejectsPaymentManagerWithoutFactoryController() public {
        vm.prank(admin);
        address treasuryAddr = factory.createTreasury(feeRecipient);
        PaymentManager standalone = new PaymentManager(admin, address(0));
        vm.prank(admin);
        vm.expectRevert(ProtocolFactory.UnauthorizedPaymentManagerController.selector);
        factory.finalizeProtocolSuiteControllers(treasuryAddr, address(standalone));
    }

    function test_CreateBlindAuctionRejectsTreasuryWithoutFactoryController() public {
        Treasury standalone = new Treasury(admin, feeRecipient, address(0));
        uint256 tokenId_ = _mint(nft, seller);
        vm.prank(seller);
        vm.expectRevert(ProtocolFactory.UnauthorizedTreasuryController.selector);
        factory.createBlindAuctionInstance(
            seller, payable(seller), address(nft), tokenId_, address(standalone), FEE_BPS, 1 days, 1 days, 1 ether
        );
    }
}

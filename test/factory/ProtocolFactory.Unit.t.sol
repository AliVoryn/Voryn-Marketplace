// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../support/TestBase.sol";

contract ProtocolFactoryUnitTest is ProtocolTestBase {
    ProtocolFactory internal factory;

    function setUp() public {
        vm.prank(admin);
        factory = new ProtocolFactory(admin);
    }

    function test_CreatePaymentManagerRegistersInstance() public {
        vm.prank(seller);
        address instance = factory.createPaymentManager();
        assertTrue(factory.registry().isRegistered(instance));
    }

    function test_CreateCustomNFTRequiresNonZeroAdmin() public {
        vm.prank(seller);
        vm.expectRevert(ProtocolFactory.ZeroAddress.selector);
        factory.createCustomNFT("X", "X", 1, address(0));
    }

    function test_PredictedDeterministicNFTMatchesDeployment() public {
        bytes32 salt = keccak256("ALI_VORYN");
        address predicted = factory.predictCustomNFTAddress(seller, "X", "X", 10, seller, salt);
        vm.prank(seller);
        address actual = factory.createCustomNFTDeterministic("X", "X", 10, seller, salt);
        assertEq(actual, predicted);
    }

    function test_CreateTreasuryRejectsZeroFeeRecipient() public {
        vm.prank(seller);
        vm.expectRevert(ProtocolFactory.ZeroAddress.selector);
        factory.createTreasury(address(0));
    }

    function test_CreateMarketplaceRejectsExternallyOwnedDependencies() public {
        vm.prank(seller);
        vm.expectRevert(ProtocolFactory.InvalidContract.selector);
        factory.createMarketplace(seller, address(0x1001), address(0x1002));
    }

    function test_CreateAuctionRejectsTreasuryWithoutFactoryController() public {
        Treasury standalone = new Treasury(seller, feeRecipient, address(0));
        vm.prank(seller);
        vm.expectRevert(ProtocolFactory.UnauthorizedTreasuryController.selector);
        factory.createAuctionInstance(address(standalone));
    }
}

contract ProtocolFactoryWiringTest is ProtocolTestBase {
    ProtocolFactory internal factory;

    function setUp() public {
        _setUpCore();
        vm.prank(admin);
        factory = new ProtocolFactory(admin);
    }

    function _record(address instance) internal view returns (IRegistry.Record memory) {
        return factory.registry().getRecord(instance);
    }

    function test_Constructor_CreatesOwnedRegistryAndMarketplaceImplementation() public view {
        assertEq(factory.registry().owner(), address(factory));
        assertGt(address(factory.marketplaceImplementation()).code.length, 0);
        assertEq(factory.owner(), admin);
    }

    function test_CreateAuctionInstance_ConfiguresOwnerFeeAndRegistry() public {
        vm.startPrank(seller);
        address treasuryAddr = factory.createTreasury(feeRecipient);
        address auctionAddr = factory.createAuctionInstance(treasuryAddr);
        vm.stopPrank();
        OpenAuction auction = OpenAuction(payable(auctionAddr));
        assertEq(auction.owner(), seller);
        assertEq(auction.protocolFeeBps(), 250);
        assertEq(auction.treasury(), treasuryAddr);
        IRegistry.Record memory record = _record(auctionAddr);
        assertEq(record.kind, factory.KIND_OPEN_AUCTION());
        assertEq(record.creator, seller);
        assertEq(record.implementation, address(0));
        assertEq(record.version, 1);
        assertTrue(record.active);
    }

    function test_CreateMarketplace_RecordsImplementationAndWiresProxy() public {
        vm.startPrank(seller);
        address treasuryAddr = factory.createTreasury(feeRecipient);
        address pmAddr = factory.createPaymentManager();
        address marketplaceAddr = factory.createMarketplace(seller, treasuryAddr, pmAddr);
        vm.stopPrank();
        Marketplace marketplace = Marketplace(marketplaceAddr);
        assertEq(marketplace.treasury(), treasuryAddr);
        assertEq(marketplace.paymentManager(), pmAddr);
        assertTrue(marketplace.hasRole(marketplace.DEFAULT_ADMIN_ROLE(), seller));
        assertTrue(Treasury(payable(treasuryAddr)).authorizedPayer(marketplaceAddr));
        assertTrue(PaymentManager(payable(pmAddr)).authorizedCreditor(marketplaceAddr));
        IRegistry.Record memory record = _record(marketplaceAddr);
        assertEq(record.kind, factory.KIND_MARKETPLACE());
        assertEq(record.implementation, address(factory.marketplaceImplementation()));
    }

    function test_CreateStaking_OwnerIsCallerAndTreasuryBound() public {
        vm.startPrank(seller);
        address treasuryAddr = factory.createTreasury(feeRecipient);
        address stakingAddr = factory.createStaking(treasuryAddr);
        vm.stopPrank();
        Staking staking = Staking(payable(stakingAddr));
        assertEq(staking.owner(), seller);
        assertEq(staking.treasury(), treasuryAddr);
        assertEq(_record(stakingAddr).kind, factory.KIND_STAKING());
    }

    function test_CreateDutchAuctionInstance_UsesProvidedOwnerAndFee() public {
        vm.prank(seller);
        address treasuryAddr = factory.createTreasury(feeRecipient);
        vm.prank(seller);
        address dutchAddr = factory.createDutchAuctionInstance(buyer, treasuryAddr, 100);
        DutchAuction dutch = DutchAuction(payable(dutchAddr));
        assertEq(dutch.owner(), buyer);
        assertEq(dutch.protocolFeeBps(), 100);
        IRegistry.Record memory record = _record(dutchAddr);
        assertEq(record.creator, buyer);
        assertEq(record.kind, factory.KIND_DUTCH_AUCTION());
    }

    function test_CreateRaffleInstance_ConfiguresVrfAndFee() public {
        MockVRFCoordinatorV2Plus coordinator = new MockVRFCoordinatorV2Plus();
        vm.prank(seller);
        address treasuryAddr = factory.createTreasury(feeRecipient);
        vm.prank(seller);
        address raffleAddr = factory.createRaffleInstance(
            buyer, treasuryAddr, 300, address(coordinator), 7, bytes32(uint256(9)), 250_000, 5, true
        );
        Raffle raffle = Raffle(payable(raffleAddr));
        assertEq(raffle.owner(), buyer);
        assertEq(raffle.treasury(), treasuryAddr);
        assertEq(raffle.feeBps(), 300);
        assertEq(raffle.vrfCoordinator(), address(coordinator));
        assertEq(raffle.subscriptionId(), 7);
        assertEq(raffle.keyHash(), bytes32(uint256(9)));
        assertEq(raffle.callbackGasLimit(), 250_000);
        assertEq(raffle.requestConfirmations(), 5);
        assertTrue(raffle.nativePayment());
        assertEq(_record(raffleAddr).creator, buyer);
    }

    function test_CreateBlindAuctionInstance_EscrowsTokenAndRegistersOwnerAsCreator() public {
        vm.prank(admin);
        address treasuryAddr = factory.createTreasury(feeRecipient);
        uint256 tokenId_ = _mint(nft, seller);
        vm.prank(seller);
        nft.setApprovalForAll(address(factory), true);
        vm.prank(seller);
        address blindAddr = factory.createBlindAuctionInstance(
            buyer, payable(seller), address(nft), tokenId_, treasuryAddr, FEE_BPS, 2 days, 1 days, 3 ether
        );
        BlindAuction blind = BlindAuction(payable(blindAddr));
        assertEq(blind.owner(), buyer);
        assertEq(blind.beneficiary(), seller);
        assertEq(blind.reservePrice(), 3 ether);
        assertEq(blind.tokenId(), tokenId_);
        assertEq(nft.ownerOf(tokenId_), blindAddr);
        assertTrue(Treasury(payable(treasuryAddr)).authorizedPayer(blindAddr));
        IRegistry.Record memory record = _record(blindAddr);
        assertEq(record.creator, buyer);
        assertEq(record.kind, factory.KIND_BLIND_AUCTION());
    }

    function test_CreateProtocolSuite_RegistersKindsAndOwnership() public {
        vm.prank(admin);
        (
            address treasuryAddr,
            address pmAddr,
            address marketplaceAddr,
            address auctionAddr,
            address stakingAddr,
            address dutchAddr
        ) = factory.createProtocolSuite(admin, feeRecipient);
        assertEq(_record(treasuryAddr).kind, factory.KIND_TREASURY());
        assertEq(_record(pmAddr).kind, factory.KIND_PAYMENT_MANAGER());
        assertEq(_record(marketplaceAddr).kind, factory.KIND_MARKETPLACE());
        assertEq(_record(marketplaceAddr).implementation, address(factory.marketplaceImplementation()));
        assertEq(_record(auctionAddr).kind, factory.KIND_OPEN_AUCTION());
        assertEq(_record(stakingAddr).kind, factory.KIND_STAKING());
        assertEq(_record(dutchAddr).kind, factory.KIND_DUTCH_AUCTION());
        assertEq(_record(auctionAddr).creator, admin);
        assertEq(OpenAuction(payable(auctionAddr)).owner(), admin);
        assertEq(Staking(payable(stakingAddr)).owner(), admin);
        assertEq(DutchAuction(payable(dutchAddr)).owner(), admin);
        assertEq(Ownable2Step(pmAddr).pendingOwner(), admin);
        assertEq(factory.creatorInstanceCount(admin), 6);
        assertEq(factory.registry().allCount(), 6);
    }

    function test_CreateFunctionsRejectExternallyOwnedTreasuriesAndManagers() public {
        vm.startPrank(seller);
        vm.expectRevert(ProtocolFactory.InvalidContract.selector);
        factory.createAuctionInstance(address(0x1234));
        vm.expectRevert(ProtocolFactory.InvalidContract.selector);
        factory.createDutchAuctionInstance(seller, address(0x1234), FEE_BPS);
        vm.expectRevert(ProtocolFactory.InvalidContract.selector);
        factory.createStaking(address(0x1234));
        vm.expectRevert(ProtocolFactory.InvalidContract.selector);
        factory.createRaffleInstance(
            seller, address(0x1234), FEE_BPS, address(1), 1, bytes32(uint256(1)), 200_000, 3, false
        );
        vm.expectRevert(ProtocolFactory.InvalidContract.selector);
        factory.createMarketplace(seller, address(treasury), address(0x1234));
        vm.stopPrank();
    }

    function test_CreatorInstanceAt_RevertsOutOfBounds() public {
        vm.expectRevert();
        factory.creatorInstanceAt(seller, 0);
    }
}

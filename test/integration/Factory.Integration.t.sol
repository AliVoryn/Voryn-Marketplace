pragma solidity ^0.8.24;
import "../helpers/TestBase.sol";
contract FactoryIntegrationTest is ProtocolTestBase {
    ProtocolFactory internal factory;
    function setUp() public {
        _setUpCore();
        vm.prank(admin);
        factory = new ProtocolFactory(admin);
    }
    function test_FINDING_TreasuryOwnershipStaysWithFactoryUntilAccepted() public {
        vm.prank(seller);
        address treasuryAddr = factory.createTreasury(feeRecipient);
        assertEq(Ownable2Step(treasuryAddr).owner(), address(factory), "factory must still be owner() until acceptOwnership()");
        assertEq(Ownable2Step(treasuryAddr).pendingOwner(), seller);
    }
    function test_FINDING_CreateMarketplace_SucceedsBeforeOwnershipAccepted() public {
        vm.startPrank(seller);
        address treasuryAddr = factory.createTreasury(feeRecipient);
        address pmAddr = factory.createPaymentManager();
        address marketplaceAddr = factory.createMarketplace(seller, treasuryAddr, pmAddr);
        vm.stopPrank();
        assertTrue(marketplaceAddr != address(0));
    }
    function test_FINDING_CreateMarketplace_RevertsAfterOwnershipAccepted() public {
        vm.startPrank(seller);
        address treasuryAddr = factory.createTreasury(feeRecipient);
        address pmAddr = factory.createPaymentManager();
        vm.stopPrank();
        vm.prank(seller);
        Ownable2Step(treasuryAddr).acceptOwnership();
        vm.prank(seller);
        vm.expectRevert(ProtocolFactory.UnauthorizedTreasuryOwner.selector);
        factory.createMarketplace(seller, treasuryAddr, pmAddr);
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
    function test_FactoryRejectsUnauthorizedTreasuryAndPaymentManagerOwners() public {
        vm.prank(seller);
        address treasuryAddr = factory.createTreasury(feeRecipient);
        vm.prank(seller);
        address paymentManagerAddr = factory.createPaymentManager();
        vm.prank(seller);
        Ownable2Step(treasuryAddr).acceptOwnership();
        vm.prank(seller);
        vm.expectRevert(ProtocolFactory.UnauthorizedTreasuryOwner.selector);
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
        assertTrue(Treasury(payable(treasuryAddr)).authorizedPayer(raffleAddr), "factory must authorize the new Raffle instance as a Treasury payer");
    }
    function test_CreateProtocolSuite_WiresAllFiveComponents() public {
        vm.prank(admin);
        (address treasuryAddr, address pmAddr, address marketplaceAddr, address auctionAddr, address stakingAddr, address dutchAuctionAddr) =
            factory.createProtocolSuite(admin, feeRecipient);
        assertTrue(treasuryAddr != address(0));
        assertTrue(pmAddr != address(0));
        assertTrue(marketplaceAddr != address(0));
        assertTrue(auctionAddr != address(0));
        assertTrue(stakingAddr != address(0));
        assertTrue(dutchAuctionAddr != address(0));
        assertEq(Ownable2Step(treasuryAddr).pendingOwner(), admin);
    }
    function test_regression_CreateBlindAuctionInstance_RequiresCallerIsBeneficiary() public {
        vm.prank(admin);
        address treasuryAddr = factory.createTreasury(feeRecipient);
        uint256 tokenId_ = _mint(nft, seller);
        vm.prank(seller);
        nft.setApprovalForAll(address(factory), true);
        vm.prank(attacker); 
        vm.expectRevert(ProtocolFactory.NotSeller.selector);
        factory.createBlindAuctionInstance(
            attacker, payable(seller), address(nft), tokenId_, treasuryAddr, FEE_BPS, 1 days, 1 days, 0.01 ether
        );
    }
    function test_regression_CreateBlindAuctionInstance_SucceedsWhenCallerIsBeneficiary() public {
        vm.prank(admin);
        address treasuryAddr = factory.createTreasury(feeRecipient);
        uint256 tokenId_ = _mint(nft, seller);
        vm.prank(seller);
        nft.setApprovalForAll(address(factory), true);
        vm.prank(seller); 
        address auctionAddr = factory.createBlindAuctionInstance(
            seller, payable(seller), address(nft), tokenId_, treasuryAddr, FEE_BPS, 1 days, 1 days, 0.01 ether
        );
        assertEq(nft.ownerOf(tokenId_), auctionAddr);
    }
}

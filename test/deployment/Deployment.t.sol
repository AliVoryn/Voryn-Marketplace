pragma solidity ^0.8.24;
import "../helpers/TestBase.sol";
contract DeploymentTest is ProtocolTestBase {
    ProtocolFactory internal factory;
    function setUp() public {
        _setUpCore();
        vm.prank(admin);
        factory = new ProtocolFactory(admin);
    }
    function test_FullSuiteDeployment_ProducesConsistentCallableGraph() public {
        vm.prank(admin);
        (address treasuryAddr, address pmAddr, address marketplaceAddr, address auctionAddr, address stakingAddr, address dutchAuctionAddr) =
            factory.createProtocolSuite(admin, feeRecipient);
        ProtocolRegistry registry = factory.registry();
        assertTrue(registry.isRegistered(treasuryAddr));
        assertTrue(registry.isRegistered(pmAddr));
        assertTrue(registry.isRegistered(marketplaceAddr));
        assertTrue(registry.isRegistered(auctionAddr));
        assertTrue(registry.isRegistered(stakingAddr));
        assertTrue(registry.isRegistered(dutchAuctionAddr));
        assertEq(Marketplace(marketplaceAddr).treasury(), treasuryAddr);
        assertEq(Marketplace(marketplaceAddr).paymentManager(), pmAddr);
        assertTrue(Marketplace(marketplaceAddr).hasRole(Marketplace(marketplaceAddr).DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(Treasury(payable(treasuryAddr)).authorizedPayer(stakingAddr));
        assertTrue(Treasury(payable(treasuryAddr)).authorizedPayer(auctionAddr));
    }
    function test_FullSuiteDeployment_EndToEndPurchaseWorksImmediately() public {
        vm.prank(admin);
        (,, address marketplaceAddr,,,) = factory.createProtocolSuite(admin, feeRecipient);
        Marketplace marketplace = Marketplace(marketplaceAddr);
        uint256 tokenId = _mint(nft, seller);
        vm.prank(seller);
        nft.approve(marketplaceAddr, tokenId);
        vm.prank(seller);
        uint256 listingId = marketplace.createListing(address(nft), tokenId, 1 ether, 0);
        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        marketplace.buy{value: 1 ether}(listingId);
        assertEq(nft.ownerOf(tokenId), buyer);
    }
}

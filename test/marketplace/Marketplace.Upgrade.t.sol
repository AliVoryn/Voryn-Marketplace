// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import "../support/TestBase.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "@openzeppelin/contracts/interfaces/IERC1967.sol";

contract MarketplaceV2Mock is Marketplace {
    function versionV2Marker() external pure returns (string memory) {
        return "v2";
    }
}

contract MarketplaceUpgradeTest is ProtocolTestBase {
    Marketplace internal marketplace;
    Marketplace internal implV1;

    function setUp() public {
        _setUpCore();
        implV1 = new Marketplace();
        bytes memory initData =
            abi.encodeCall(Marketplace.initialize, (admin, address(treasury), address(paymentManager)));
        ERC1967Proxy proxy = new ERC1967Proxy(address(implV1), initData);
        marketplace = Marketplace(address(proxy));
    }

    function test_DirectImplementationCannotBeInitialized() public {
        vm.expectRevert();
        implV1.initialize(admin, address(treasury), address(paymentManager));
    }

    function test_ProxyCannotBeReInitialized() public {
        vm.expectRevert();
        marketplace.initialize(admin, address(treasury), address(paymentManager));
    }

    function test_Upgrade_RevertsForUnauthorizedCaller() public {
        MarketplaceV2Mock implV2 = new MarketplaceV2Mock();
        vm.prank(attacker);
        vm.expectRevert();
        marketplace.upgradeToAndCall(address(implV2), "");
    }

    function test_Upgrade_AuthorizedAdmin_PreservesState() public {
        uint256 tokenId = _mint(nft, seller);
        vm.prank(seller);
        nft.approve(address(marketplace), tokenId);
        vm.prank(seller);
        uint256 listingId = marketplace.createListing(address(nft), tokenId, 1 ether, 0);
        MarketplaceV2Mock implV2 = new MarketplaceV2Mock();
        vm.prank(admin);
        marketplace.upgradeToAndCall(address(implV2), "");
        IMarketplace.Listing memory l = marketplace.getListing(listingId);
        assertEq(l.seller, seller);
        assertEq(l.price, 1 ether);
        assertEq(MarketplaceV2Mock(address(marketplace)).versionV2Marker(), "v2");
    }

    function test_Upgrade_EmitsUpgradedByProtocolEvent() public {
        MarketplaceV2Mock implV2 = new MarketplaceV2Mock();
        vm.prank(admin);
        vm.expectEmit(true, true, false, false, address(marketplace));
        emit IERC1967.Upgraded(address(implV2));
        marketplace.upgradeToAndCall(address(implV2), "");
    }
}

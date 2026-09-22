// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../support/TestBase.sol";

contract ReentrantMarketplaceBuyer is IERC721Receiver {
    Marketplace internal immutable marketplace;
    uint256 internal immutable listingId;
    uint256 internal immutable price;
    bool public attempted;
    bool public reentrantCallSucceeded;

    constructor(Marketplace marketplace_, uint256 listingId_, uint256 price_) {
        marketplace = marketplace_;
        listingId = listingId_;
        price = price_;
    }

    receive() external payable { }

    function purchase() external {
        marketplace.buy{ value: price }(listingId);
    }

    function onERC721Received(address, address, uint256, bytes calldata) external returns (bytes4) {
        if (!attempted) {
            attempted = true;
            try marketplace.buy{ value: price }(listingId) {
                reentrantCallSucceeded = true;
            } catch { }
        }
        return IERC721Receiver.onERC721Received.selector;
    }
}

contract MarketplaceSecurityTest is ProtocolTestBase {
    Marketplace internal marketplace;
    uint256 internal tokenId;

    function setUp() public {
        _setUpCore();
        marketplace = _deployMarketplaceProxy(address(treasury), address(paymentManager));
        vm.prank(admin);
        treasury.setAuthorizedPayer(address(marketplace), true);
        tokenId = _mint(nft, seller);
        vm.prank(seller);
        nft.approve(address(marketplace), tokenId);
    }

    function test_BuyIsProtectedAgainstReceiverReentrancy() public {
        vm.prank(seller);
        uint256 listingId = marketplace.createListing(address(nft), tokenId, 1 ether, 0);
        ReentrantMarketplaceBuyer receiver = new ReentrantMarketplaceBuyer(marketplace, listingId, 1 ether);
        vm.deal(address(receiver), 2 ether);
        receiver.purchase();
        assertTrue(receiver.attempted());
        assertFalse(receiver.reentrantCallSucceeded());
        assertEq(nft.ownerOf(tokenId), address(receiver));
        assertEq(uint8(marketplace.getListing(listingId).status), uint8(IMarketplace.ListingStatus.Sold));
        assertEq(treasury.claimable(seller), 0.975 ether);
        assertEq(address(receiver).balance, 1 ether);
    }

    function test_BuyRejectsSellerAsBuyer() public {
        vm.prank(seller);
        uint256 listingId = marketplace.createListing(address(nft), tokenId, 1 ether, 0);
        vm.deal(seller, 1 ether);
        vm.prank(seller);
        vm.expectRevert(IMarketplace.CannotBuyOwnListing.selector);
        marketplace.buy{ value: 1 ether }(listingId);
    }

    function test_AdminControlsAreNotCallableByUnauthorizedAccount() public {
        vm.startPrank(attacker);
        vm.expectRevert();
        marketplace.pause();
        vm.expectRevert();
        marketplace.setTreasury(address(treasury));
        vm.expectRevert();
        marketplace.setPaymentManager(address(paymentManager));
        vm.expectRevert();
        marketplace.setProtocolFee(500);
        vm.stopPrank();
    }

    function test_PauseBlocksUserStateTransitions() public {
        vm.prank(admin);
        marketplace.pause();

        vm.prank(seller);
        vm.expectRevert();
        marketplace.createListing(address(nft), tokenId, 1 ether, 0);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../../support/TestBase.sol";

contract DutchAuctionSecurityTest is ProtocolTestBase {
    DutchAuction internal auction;
    uint256 internal tokenId;

    function setUp() public {
        _setUpCore();
        auction = _deployDutchAuction(address(treasury));
        tokenId = _mint(nft, seller);
        vm.prank(seller);
        nft.approve(address(auction), tokenId);
    }

    function test_SellerCannotBuyOwnAuction() public {
        vm.prank(seller);
        uint256 id = auction.createAuction(address(nft), tokenId, 2 ether, 1 ether, 0, 1 days);
        vm.deal(seller, 2 ether);
        vm.prank(seller);
        vm.expectRevert(IDutchAuction.NotSeller.selector);
        auction.buy{ value: 2 ether }(id);
    }

    function test_UnauthorizedCannotPauseOrUnpause() public {
        vm.prank(attacker);
        vm.expectRevert();
        auction.pause();
        vm.prank(attacker);
        vm.expectRevert();
        auction.unpause();
    }

    function test_UnauthorizedCannotCancel() public {
        vm.prank(seller);
        uint256 id = auction.createAuction(address(nft), tokenId, 2 ether, 1 ether, 0, 1 days);
        vm.prank(attacker);
        vm.expectRevert(IDutchAuction.NotSeller.selector);
        auction.cancelAuction(id);
    }
}

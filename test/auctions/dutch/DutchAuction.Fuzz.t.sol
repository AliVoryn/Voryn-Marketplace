// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../../support/TestBase.sol";

contract DutchAuctionFuzzTest is ProtocolTestBase {
    DutchAuction internal auction;
    uint256 internal tokenId;

    function setUp() public {
        _setUpCore();
        auction = _deployDutchAuction(address(treasury));
        tokenId = _mint(nft, seller);
        vm.prank(seller);
        nft.approve(address(auction), tokenId);
    }

    function testFuzz_CurrentPriceNeverExitsConfiguredRange(uint32 offset) public {
        uint64 duration = 1 days;
        uint64 endOffset = uint64(bound(uint256(offset), 0, duration));
        vm.prank(seller);
        uint256 id = auction.createAuction(address(nft), tokenId, 2 ether, 1 ether, 0, duration);
        vm.warp(block.timestamp + endOffset);
        uint256 price = auction.currentPrice(id);
        assertLe(price, 2 ether);
        assertGe(price, 1 ether);
    }
}

contract DutchAuctionAdditionalFuzzTest is ProtocolTestBase {
    DutchAuction internal auction;
    uint256 internal tokenId;

    function setUp() public {
        _setUpCore();
        auction = _deployDutchAuction(address(treasury));
        vm.prank(admin);
        treasury.setAuthorizedPayer(address(auction), true);
        tokenId = _mint(nft, seller);
        vm.prank(seller);
        nft.approve(address(auction), tokenId);
    }

    function testFuzz_CurrentPriceIsMonotonic(uint32 first, uint32 second) public {
        uint256 t1 = bound(uint256(first), 0, 1 days);
        uint256 t2 = bound(uint256(second), t1, 1 days);
        vm.prank(seller);
        uint256 id = auction.createAuction(address(nft), tokenId, 2 ether, 1 ether, 0, 1 days);
        uint256 price1 = auction.currentPrice(id);
        vm.warp(block.timestamp + t1);
        price1 = auction.currentPrice(id);
        vm.warp(block.timestamp + (t2 - t1));
        uint256 price2 = auction.currentPrice(id);
        assertLe(price2, price1);
        assertGe(price2, 1 ether);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../../support/TestBase.sol";

contract BlindAuctionFuzzTest is ProtocolTestBase {
    BlindAuction internal auction;
    uint256 internal tokenId;

    function setUp() public {
        _setUpCore();
        tokenId = _mint(nft, seller);
        auction = new BlindAuction(
            admin, payable(seller), address(nft), tokenId, address(treasury), FEE_BPS, 1 days, 1 days, 1 ether
        );
        vm.prank(seller);
        nft.approve(address(auction), tokenId);
        vm.prank(seller);
        nft.transferFrom(seller, address(auction), tokenId);
    }

    function testFuzz_ComputeBlindedBid_IsDeterministic(uint256 value, bool fake, bytes32 secret) public view {
        bytes32 first = auction.computeBlindedBid(value, fake, secret);
        bytes32 second = auction.computeBlindedBid(value, fake, secret);
        assertEq(first, second);
    }

    function testFuzz_RevealFakeBidAlwaysReturnsItsDeposit(uint96 rawDeposit) public {
        uint256 deposit = bound(uint256(rawDeposit), 1, 5 ether);
        bytes32 secret = bytes32(uint256(123));
        bytes32 blinded = auction.computeBlindedBid(1 ether, true, secret);
        vm.deal(buyer, deposit);
        vm.prank(buyer);
        auction.placeBid{ value: deposit }(blinded);
        vm.warp(block.timestamp + 1 days + 1);
        uint256[] memory values = new uint256[](1);
        bool[] memory fakes = new bool[](1);
        bytes32[] memory secrets = new bytes32[](1);
        values[0] = 1 ether;
        fakes[0] = true;
        secrets[0] = secret;
        vm.prank(buyer);
        auction.reveal(values, fakes, secrets);
        assertEq(auction.getPendingReturn(buyer), deposit);
        assertEq(auction.highestBid(), 0);
        vm.prank(buyer);
        auction.withdraw();
        assertEq(buyer.balance, deposit);
    }
}

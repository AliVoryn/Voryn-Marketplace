// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../../support/TestBase.sol";

contract BlindAuctionTreasuryIntegrationTest is ProtocolTestBase {
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
        vm.prank(admin);
        treasury.setAuthorizedPayer(address(auction), true);
    }

    function test_WinningSettlementFlowsIntoTreasuryAndTransfersNFT() public {
        bytes32 secret = keccak256("winner");
        bytes32 commitment = auction.computeBlindedBid(2 ether, false, secret);
        vm.deal(buyer, 2 ether);
        vm.prank(buyer);
        auction.placeBid{ value: 2 ether }(commitment);

        vm.warp(block.timestamp + 1 days + 1);
        uint256[] memory values = new uint256[](1);
        values[0] = 2 ether;
        bool[] memory fakes = new bool[](1);
        bytes32[] memory secrets = new bytes32[](1);
        secrets[0] = secret;
        vm.prank(buyer);
        auction.reveal(values, fakes, secrets);

        vm.warp(block.timestamp + 1 days + 1);
        auction.finalizeAuction();

        assertEq(nft.ownerOf(tokenId), buyer);
        assertEq(treasury.claimable(seller), 1.95 ether);
        assertEq(treasury.claimable(feeRecipient), 0.05 ether);
        assertEq(auction.totalUnrevealedDeposits(), 0);
        assertEq(address(auction).balance, auction.totalPendingReturns());
    }
}

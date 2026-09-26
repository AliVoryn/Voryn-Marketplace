// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../../support/TestBase.sol";

contract BlindAuctionInvariantHandler is Test {
    BlindAuction internal auction;
    uint256[] internal values;
    bool[] internal fakes;
    bytes32[] internal secrets;

    constructor(BlindAuction auction_) {
        auction = auction_;
    }

    function placeBid(uint96 rawValue, bool fake, bytes32 secret) external {
        if (auction.currentPhase() != IBlindAuction.Phase.Bidding) return;
        uint256 value = bound(uint256(rawValue), 1 wei, 5 ether);
        if (values.length >= auction.MAX_BIDS_PER_ADDRESS()) return;
        values.push(value);
        fakes.push(fake);
        secrets.push(secret);
        vm.deal(address(this), address(this).balance + value);
        auction.placeBid{ value: value }(auction.computeBlindedBid(value, fake, secret));
    }

    function moveToReveal() external {
        IBlindAuction.Phase phase = auction.currentPhase();
        if (phase != IBlindAuction.Phase.Bidding) return;
        vm.warp(auction.biddingEnd() + 1);
    }

    function revealAll() external {
        if (auction.currentPhase() != IBlindAuction.Phase.Reveal) return;
        uint256 length = values.length;
        if (length == 0) return;
        auction.reveal(values, fakes, secrets);
    }
}

contract BlindAuctionInvariantTest is StdInvariant, ProtocolTestBase {
    BlindAuction internal auction;
    BlindAuctionInvariantHandler internal handler;

    function setUp() public {
        _setUpCore();
        uint256 tokenId = _mint(nft, seller);
        auction = new BlindAuction(
            admin, payable(seller), address(nft), tokenId, address(treasury), FEE_BPS, 1 days, 1 days, 1 ether
        );
        vm.prank(seller);
        nft.approve(address(this), tokenId);
        vm.prank(seller);
        nft.transferFrom(seller, address(auction), tokenId);
        handler = new BlindAuctionInvariantHandler(auction);
        targetContract(address(handler));
    }

    function invariant_EscrowCoversAllBlindAuctionLiabilities() public view {
        assertGe(
            address(auction).balance,
            auction.highestBid() + auction.totalPendingReturns() + auction.totalUnrevealedDeposits()
        );
    }
}

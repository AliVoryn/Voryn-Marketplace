// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../../support/TestBase.sol";

contract BlindAuctionSecurityTest is ProtocolTestBase {
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

    function test_NonOwnerCannotCancel() public {
        vm.prank(attacker);
        vm.expectRevert();
        auction.cancelAuction();
    }

    function test_BeneficiaryCannotBid() public {
        bytes32 blinded = auction.computeBlindedBid(1 ether, false, bytes32(uint256(1)));
        vm.deal(seller, 1 ether);
        vm.prank(seller);
        vm.expectRevert(IBlindAuction.SellerCannotBid.selector);
        auction.placeBid{ value: 1 ether }(blinded);
    }

    function test_PausedAuctionBlocksMutationUntilOwnerUnpauses() public {
        vm.prank(admin);
        auction.pause();
        vm.deal(buyer, 1 ether);
        bytes32 blinded = auction.computeBlindedBid(1 ether, false, bytes32(uint256(1)));
        vm.prank(buyer);
        vm.expectRevert();
        auction.placeBid{ value: 1 ether }(blinded);
        vm.prank(admin);
        auction.unpause();
        vm.prank(buyer);
        auction.placeBid{ value: 1 ether }(blinded);
        assertEq(auction.getBidCount(buyer), 1);
    }
}

contract BlindAuctionAdditionalSecurityTest is ProtocolTestBase {
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

    function test_RevealRejectsMismatchedArrayLengths() public {
        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        auction.placeBid{ value: 1 ether }(auction.computeBlindedBid(1 ether, false, bytes32(uint256(1))));
        vm.warp(block.timestamp + 1 days + 1);
        uint256[] memory values = new uint256[](0);
        bool[] memory fakes = new bool[](1);
        bytes32[] memory secrets = new bytes32[](1);
        vm.prank(buyer);
        vm.expectRevert(IBlindAuction.ArrayLengthMismatch.selector);
        auction.reveal(values, fakes, secrets);
    }

    function test_CancelledAuctionAllowsUnrevealedAndPendingRefundsOnce() public {
        vm.deal(buyer, 2 ether);
        bytes32 blind = auction.computeBlindedBid(1 ether, false, bytes32(uint256(7)));
        vm.prank(buyer);
        auction.placeBid{ value: 1 ether }(blind);
        vm.prank(admin);
        auction.cancelAuction();
        uint256 before = buyer.balance;
        vm.prank(buyer);
        auction.withdrawIfCancelled();
        assertEq(buyer.balance, before + 1 ether);
        vm.prank(buyer);
        vm.expectRevert(IBlindAuction.NothingToWithdraw.selector);
        auction.withdrawIfCancelled();
    }

    function test_CopiedCommitmentCannotBeSubmittedByAnotherBidder() public {
        bytes32 victimCommitment = auction.computeBlindedBid(2 ether, false, bytes32(uint256(77)));
        vm.deal(buyer, 4 ether);
        vm.prank(buyer);
        auction.placeBid{ value: 2 ether }(victimCommitment);
        assertTrue(auction.commitmentUsed(victimCommitment));
        vm.deal(attacker, 5 ether);
        vm.prank(attacker);
        vm.expectRevert(BlindAuction.CommitmentAlreadyUsed.selector);
        auction.placeBid{ value: 5 ether }(victimCommitment);
        vm.prank(buyer);
        vm.expectRevert(BlindAuction.CommitmentAlreadyUsed.selector);
        auction.placeBid{ value: 2 ether }(victimCommitment);
        assertEq(auction.getBidCount(attacker), 0);
        assertEq(auction.totalUnrevealedDeposits(), 2 ether);
    }

    function test_NonOwnerCannotPauseOrUnpause() public {
        vm.prank(attacker);
        vm.expectRevert();
        auction.pause();
        vm.prank(admin);
        auction.pause();
        vm.prank(attacker);
        vm.expectRevert();
        auction.unpause();
    }

    function test_UnrevealedWithdrawalCannotBeReentered() public {
        ReentrantBlindBidder bidder = new ReentrantBlindBidder(auction);
        vm.deal(address(bidder), 1 ether);
        bidder.bid(auction.computeBlindedBid(1 ether, false, bytes32(uint256(11))), 1 ether);
        vm.warp(block.timestamp + 2 days + 1);
        vm.expectRevert(IBlindAuction.TransferFailed.selector);
        bidder.pull();
        assertEq(auction.totalUnrevealedDeposits(), 1 ether);
        assertEq(address(auction).balance, 1 ether);
    }
}

contract ReentrantBlindBidder {
    BlindAuction internal immutable auction;

    constructor(BlindAuction auction_) {
        auction = auction_;
    }

    function bid(bytes32 commitment, uint256 deposit) external {
        auction.placeBid{ value: deposit }(commitment);
    }

    function pull() external {
        auction.withdrawUnrevealed();
    }

    receive() external payable {
        auction.withdrawUnrevealed();
    }
}

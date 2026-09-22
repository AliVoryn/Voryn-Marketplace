// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../../support/TestBase.sol";

contract BlindAuctionRegressionTest is ProtocolTestBase {
    uint256 internal tokenId;

    function setUp() public {
        _setUpCore();
        tokenId = _mint(nft, seller);
    }

    function _newAuction(uint256 biddingTime, uint256 revealTime) internal returns (BlindAuction) {
        return new BlindAuction(
            admin, payable(seller), address(nft), tokenId, address(treasury), FEE_BPS, biddingTime, revealTime, 1 ether
        );
    }

    function _deployBlindAuctionDirect() internal returns (BlindAuction auction) {
        auction = _newAuction(1 days, 1 days);
        vm.prank(admin);
        treasury.setAuthorizedPayer(address(auction), true);
        vm.prank(seller);
        nft.approve(address(this), tokenId);
        nft.transferFrom(seller, address(auction), tokenId);
    }

    function test_InvalidRevealDoesNotConsumeRevealExtension() public {
        BlindAuction auction = _deployBlindAuctionDirect();
        bytes32 secret = keccak256("valid");
        bytes32 commitment = auction.computeBlindedBid(1 ether, false, secret);
        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        auction.placeBid{ value: 1 ether }(commitment);

        vm.warp(auction.revealEnd() - 1 minutes);
        uint256 revealEndBefore = auction.revealEnd();
        uint256[] memory values = new uint256[](1);
        values[0] = 1 ether;
        bool[] memory fakes = new bool[](1);
        bytes32[] memory secrets = new bytes32[](1);
        secrets[0] = keccak256("wrong");

        vm.prank(buyer);
        auction.reveal(values, fakes, secrets);

        assertEq(auction.revealExtensionsUsed(), 0);
        assertEq(auction.revealEnd(), revealEndBefore);
        assertEq(auction.getPendingReturn(buyer), 0);
    }

    function test_Constructor_RejectsTimeSumOverflowWithInvalidTimesInsteadOfPanic() public {
        uint256 maxTime = type(uint64).max;
        vm.expectRevert(IBlindAuction.InvalidTimes.selector);
        _newAuction(1, maxTime);
        vm.expectRevert(IBlindAuction.InvalidTimes.selector);
        _newAuction(maxTime, 1);
        vm.expectRevert(IBlindAuction.InvalidTimes.selector);
        _newAuction(maxTime, maxTime);
    }

    function test_Constructor_RejectsSingleDurationsBeyondUint64() public {
        uint256 beyond = uint256(type(uint64).max) + 1;
        vm.expectRevert(IBlindAuction.InvalidTimes.selector);
        _newAuction(beyond, 1 days);
        vm.expectRevert(IBlindAuction.InvalidTimes.selector);
        _newAuction(1 days, beyond);
    }

    function test_Constructor_AcceptsLargestSchedulableWindow() public {
        uint256 remaining = uint256(type(uint64).max) - block.timestamp;
        BlindAuction auction = _newAuction(remaining - 1, 1);
        assertEq(auction.revealEnd(), type(uint64).max);
    }

    function test_CopiedCommitmentCannotDisplaceTheOriginalBidderAtReveal() public {
        BlindAuction auction = _newAuction(1 days, 1 days);
        vm.prank(seller);
        nft.approve(address(this), tokenId);
        vm.prank(seller);
        nft.transferFrom(seller, address(auction), tokenId);
        vm.prank(admin);
        treasury.setAuthorizedPayer(address(auction), true);

        bytes32 secret = keccak256("victim-secret");
        bytes32 commitment = auction.computeBlindedBid(2 ether, false, secret);
        vm.deal(buyer, 2 ether);
        vm.prank(buyer);
        auction.placeBid{ value: 2 ether }(commitment);
        vm.deal(attacker, 10 ether);
        vm.prank(attacker);
        vm.expectRevert(BlindAuction.CommitmentAlreadyUsed.selector);
        auction.placeBid{ value: 10 ether }(commitment);

        vm.warp(block.timestamp + 1 days + 1);
        uint256[] memory values = new uint256[](1);
        bool[] memory fakes = new bool[](1);
        bytes32[] memory secrets = new bytes32[](1);
        values[0] = 2 ether;
        secrets[0] = secret;
        vm.prank(buyer);
        auction.reveal(values, fakes, secrets);
        assertEq(auction.highestBidder(), buyer);
        vm.warp(block.timestamp + 1 days + 1);
        auction.finalizeAuction();
        assertEq(nft.ownerOf(tokenId), buyer);
    }
}

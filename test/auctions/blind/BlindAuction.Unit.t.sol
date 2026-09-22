// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import "../../support/TestBase.sol";

contract BlindAuctionCommitRevealTest is ProtocolTestBase {
    uint256 internal constant BIDDING_TIME = 1 days;
    uint256 internal constant REVEAL_TIME = 1 days;
    uint256 internal constant RESERVE = 1 ether;
    uint256 internal tokenId;

    function _deployBlindAuctionDirect() internal returns (BlindAuction auction) {
        tokenId = _mint(nft, seller);
        auction = new BlindAuction(
            admin,
            payable(seller),
            address(nft),
            tokenId,
            address(treasury),
            FEE_BPS,
            BIDDING_TIME,
            REVEAL_TIME,
            RESERVE
        );
        vm.prank(admin);
        treasury.setAuthorizedPayer(address(auction), true);
        vm.prank(seller);
        nft.approve(address(this), tokenId);
        nft.transferFrom(seller, address(auction), tokenId);
    }

    function _blindBid(BlindAuction auction, uint256 value, bool fake, bytes32 secret) internal pure returns (bytes32) {
        auction;
        return keccak256(abi.encodePacked(value, fake, secret));
    }

    function setUp() public {
        _setUpCore();
    }

    function test_PlaceBid_DuringBiddingPhase() public {
        BlindAuction auction = _deployBlindAuctionDirect();
        bytes32 blinded = _blindBid(auction, 2 ether, false, keccak256("secret1"));
        vm.deal(buyer, 2 ether);
        vm.prank(buyer);
        auction.placeBid{ value: 2 ether }(blinded);
        assertEq(auction.getBidCount(buyer), 1);
    }

    function test_PlaceBid_RevertsBeforeNFTIsEscrowed() public {
        tokenId = _mint(nft, seller);
        BlindAuction auction = new BlindAuction(
            admin,
            payable(seller),
            address(nft),
            tokenId,
            address(treasury),
            FEE_BPS,
            BIDDING_TIME,
            REVEAL_TIME,
            RESERVE
        );
        bytes32 blinded = auction.computeBlindedBid(2 ether, false, bytes32(uint256(1)));
        vm.deal(buyer, 2 ether);
        vm.prank(buyer);
        vm.expectRevert(BlindAuction.SellerNoLongerOwnsAsset.selector);
        auction.placeBid{ value: 2 ether }(blinded);
    }

    function test_PlaceBid_RevertsOutsideBiddingPhase() public {
        BlindAuction auction = _deployBlindAuctionDirect();
        vm.warp(block.timestamp + BIDDING_TIME + 1);
        bytes32 blinded = _blindBid(auction, 2 ether, false, keccak256("secret1"));
        vm.deal(buyer, 2 ether);
        vm.prank(buyer);
        vm.expectRevert();
        auction.placeBid{ value: 2 ether }(blinded);
    }

    function test_Reveal_HonestBidBecomesHighest() public {
        BlindAuction auction = _deployBlindAuctionDirect();
        bytes32 secret = keccak256("secret1");
        bytes32 blinded = _blindBid(auction, 2 ether, false, secret);
        vm.deal(buyer, 2 ether);
        vm.prank(buyer);
        auction.placeBid{ value: 2 ether }(blinded);
        vm.warp(block.timestamp + BIDDING_TIME + 1);
        uint256[] memory values = new uint256[](1);
        values[0] = 2 ether;
        bool[] memory fakes = new bool[](1);
        fakes[0] = false;
        bytes32[] memory secrets = new bytes32[](1);
        secrets[0] = secret;
        vm.prank(buyer);
        auction.reveal(values, fakes, secrets);
        assertEq(auction.highestBidder(), buyer);
        assertEq(auction.highestBid(), 2 ether);
    }

    function test_Reveal_FakeBidIsFullyRefundable() public {
        BlindAuction auction = _deployBlindAuctionDirect();
        bytes32 secret = keccak256("secret1");
        bytes32 blinded = _blindBid(auction, 2 ether, true, secret);
        vm.deal(buyer, 3 ether);
        vm.prank(buyer);
        auction.placeBid{ value: 3 ether }(blinded);
        vm.warp(block.timestamp + BIDDING_TIME + 1);
        uint256[] memory values = new uint256[](1);
        values[0] = 2 ether;
        bool[] memory fakes = new bool[](1);
        fakes[0] = true;
        bytes32[] memory secrets = new bytes32[](1);
        secrets[0] = secret;
        vm.prank(buyer);
        auction.reveal(values, fakes, secrets);
        assertEq(auction.highestBidder(), address(0), "a fake bid must never become the highest bid");
        assertEq(auction.getPendingReturn(buyer), 3 ether, "full deposit must be refundable for a fake bid");
    }

    function test_Reveal_MismatchedReveal_RemainsRecoverableAfterRevealWindow() public {
        BlindAuction auction = _deployBlindAuctionDirect();
        bytes32 secret = keccak256("secret1");
        bytes32 blinded = _blindBid(auction, 2 ether, false, secret);
        vm.deal(buyer, 2 ether);
        vm.prank(buyer);
        auction.placeBid{ value: 2 ether }(blinded);
        vm.warp(block.timestamp + BIDDING_TIME + 1);
        uint256[] memory values = new uint256[](1);
        values[0] = 999 ether;
        bool[] memory fakes = new bool[](1);
        fakes[0] = false;
        bytes32[] memory secrets = new bytes32[](1);
        secrets[0] = secret;
        vm.prank(buyer);
        auction.reveal(values, fakes, secrets);
        assertEq(auction.getPendingReturn(buyer), 0);
        vm.warp(block.timestamp + REVEAL_TIME + 1);
        uint256 before = buyer.balance;
        vm.prank(buyer);
        auction.withdrawUnrevealed();
        assertEq(buyer.balance, before + 2 ether);
    }

    function test_Finalize_ReserveMet_PaysSellerAndReleasesNFT() public {
        BlindAuction auction = _deployBlindAuctionDirect();
        bytes32 secret = keccak256("secret1");
        bytes32 blinded = _blindBid(auction, 2 ether, false, secret);
        vm.deal(buyer, 2 ether);
        vm.prank(buyer);
        auction.placeBid{ value: 2 ether }(blinded);
        vm.warp(block.timestamp + BIDDING_TIME + 1);
        uint256[] memory values = new uint256[](1);
        values[0] = 2 ether;
        bool[] memory fakes = new bool[](1);
        fakes[0] = false;
        bytes32[] memory secrets = new bytes32[](1);
        secrets[0] = secret;
        vm.prank(buyer);
        auction.reveal(values, fakes, secrets);
        vm.warp(block.timestamp + REVEAL_TIME + 1);
        auction.finalizeAuction();
        assertEq(nft.ownerOf(tokenId), buyer);
        assertEq(treasury.claimable(seller), 1.95 ether);
        assertGe(address(auction).balance, auction.totalPendingReturns());
    }

    function test_Finalize_AllowsUnrevealedDepositRecovery() public {
        BlindAuction auction = _deployBlindAuctionDirect();
        bytes32 blinded = _blindBid(auction, 2 ether, false, keccak256("unrevealed"));
        vm.deal(buyer, 2 ether);
        vm.prank(buyer);
        auction.placeBid{ value: 2 ether }(blinded);
        vm.warp(block.timestamp + BIDDING_TIME + REVEAL_TIME + 2);
        auction.finalizeAuction();
        assertEq(nft.ownerOf(tokenId), seller);
        uint256 before = buyer.balance;
        vm.prank(buyer);
        auction.withdrawUnrevealed();
        assertEq(buyer.balance, before + 2 ether);
    }

    function test_Finalize_ReserveNotMet_ReturnsNFTToBeneficiary() public {
        BlindAuction auction = _deployBlindAuctionDirect();
        vm.warp(block.timestamp + BIDDING_TIME + REVEAL_TIME + 2);
        auction.finalizeAuction();
        assertEq(nft.ownerOf(tokenId), seller);
    }

    function test_Finalize_RevertsBeforeAwaitingFinalizationPhase() public {
        BlindAuction auction = _deployBlindAuctionDirect();
        vm.expectRevert();
        auction.finalizeAuction();
    }

    function test_Cancel_RefundsHighestBidderAndReturnsNFT() public {
        BlindAuction auction = _deployBlindAuctionDirect();
        bytes32 secret = keccak256("secret1");
        bytes32 blinded = _blindBid(auction, 2 ether, false, secret);
        vm.deal(buyer, 2 ether);
        vm.prank(buyer);
        auction.placeBid{ value: 2 ether }(blinded);
        vm.warp(block.timestamp + BIDDING_TIME + 1);
        uint256[] memory values = new uint256[](1);
        values[0] = 2 ether;
        bool[] memory fakes = new bool[](1);
        fakes[0] = false;
        bytes32[] memory secrets = new bytes32[](1);
        secrets[0] = secret;
        vm.prank(buyer);
        auction.reveal(values, fakes, secrets);
        vm.prank(admin);
        auction.cancelAuction();
        assertEq(nft.ownerOf(tokenId), seller);
        assertEq(auction.getPendingReturn(buyer), 2 ether);
    }

    function test_WithdrawIfCancelled_RefundsUnrevealedDeposits() public {
        BlindAuction auction = _deployBlindAuctionDirect();
        bytes32 blinded = _blindBid(auction, 2 ether, false, keccak256("secret1"));
        vm.deal(buyer, 2 ether);
        vm.prank(buyer);
        auction.placeBid{ value: 2 ether }(blinded);
        vm.prank(admin);
        auction.cancelAuction();
        uint256 before = buyer.balance;
        vm.prank(buyer);
        auction.withdrawIfCancelled();
        assertEq(buyer.balance, before + 2 ether);
    }

    function test_Reveal_LowerBidIsRefundedWithoutReplacingHighest() public {
        BlindAuction auction = _deployBlindAuctionDirect();
        bytes32 highSecret = keccak256("high");
        bytes32 lowSecret = keccak256("low");
        vm.deal(buyer, 2 ether);
        vm.prank(buyer);
        auction.placeBid{ value: 2 ether }(_blindBid(auction, 2 ether, false, highSecret));
        vm.deal(buyer2, 1 ether);
        vm.prank(buyer2);
        auction.placeBid{ value: 1 ether }(_blindBid(auction, 1 ether, false, lowSecret));
        vm.warp(block.timestamp + BIDDING_TIME + 1);

        uint256[] memory highValues = new uint256[](1);
        highValues[0] = 2 ether;
        bool[] memory highFakes = new bool[](1);
        bytes32[] memory highSecrets = new bytes32[](1);
        highSecrets[0] = highSecret;
        vm.prank(buyer);
        auction.reveal(highValues, highFakes, highSecrets);

        uint256[] memory lowValues = new uint256[](1);
        lowValues[0] = 1 ether;
        bool[] memory lowFakes = new bool[](1);
        bytes32[] memory lowSecrets = new bytes32[](1);
        lowSecrets[0] = lowSecret;
        vm.prank(buyer2);
        auction.reveal(lowValues, lowFakes, lowSecrets);

        assertEq(auction.highestBidder(), buyer);
        assertEq(auction.highestBid(), 2 ether);
        assertEq(auction.getPendingReturn(buyer2), 1 ether);
    }

    function test_Cancel_WithHighestBid_AllowsCombinedCancelledRefund() public {
        BlindAuction auction = _deployBlindAuctionDirect();
        bytes32 secret = keccak256("cancel");
        vm.deal(buyer, 2 ether);
        vm.prank(buyer);
        auction.placeBid{ value: 2 ether }(_blindBid(auction, 2 ether, false, secret));
        vm.warp(block.timestamp + BIDDING_TIME + 1);
        uint256[] memory values = new uint256[](1);
        values[0] = 2 ether;
        bool[] memory fakes = new bool[](1);
        bytes32[] memory secrets = new bytes32[](1);
        secrets[0] = secret;
        vm.prank(buyer);
        auction.reveal(values, fakes, secrets);
        vm.prank(admin);
        auction.cancelAuction();

        uint256 before = buyer.balance;
        vm.prank(buyer);
        auction.withdrawIfCancelled();
        assertEq(buyer.balance, before + 2 ether);
        assertEq(auction.getPendingReturn(buyer), 0);
    }

    function test_Pause_BlocksBidAndRevealUntilUnpaused() public {
        BlindAuction auction = _deployBlindAuctionDirect();
        vm.prank(admin);
        auction.pause();
        vm.deal(buyer, 1 ether);
        bytes32 blinded = _blindBid(auction, 1 ether, false, keccak256("paused"));
        vm.prank(buyer);
        vm.expectRevert();
        auction.placeBid{ value: 1 ether }(blinded);
        vm.prank(admin);
        auction.unpause();
        vm.prank(buyer);
        auction.placeBid{ value: 1 ether }(blinded);
        vm.warp(block.timestamp + BIDDING_TIME + 1);
        uint256[] memory values = new uint256[](1);
        values[0] = 1 ether;
        bool[] memory fakes = new bool[](1);
        bytes32[] memory secrets = new bytes32[](1);
        secrets[0] = keccak256("paused");
        vm.prank(admin);
        auction.pause();
        vm.prank(buyer);
        vm.expectRevert();
        auction.reveal(values, fakes, secrets);
    }

    function test_Views_ReportAuctionState() public {
        BlindAuction auction = _deployBlindAuctionDirect();
        assertEq(uint8(auction.currentPhase()), uint8(IBlindAuction.Phase.Bidding));
        assertGt(auction.timeUntilPhaseChange(), 0);
        assertEq(auction.biddingEnd(), block.timestamp + BIDDING_TIME);
        assertEq(auction.revealEnd(), block.timestamp + BIDDING_TIME + REVEAL_TIME);
        assertEq(auction.revealExtensionsUsed(), 0);
        assertFalse(auction.auctionEnded());
        assertFalse(auction.auctionCancelled());
        vm.prank(buyer);
        assertEq(auction.getMyBidCount(), 0);
    }

    function test_Constructor_RevertsOnEachInvalidInput() public {
        uint256 id = _mint(nft, seller);
        vm.expectRevert(IBlindAuction.ZeroAddress.selector);
        new BlindAuction(
            admin, payable(address(0)), address(nft), id, address(treasury), FEE_BPS, BIDDING_TIME, REVEAL_TIME, RESERVE
        );
        vm.expectRevert(IBlindAuction.ZeroAddress.selector);
        new BlindAuction(
            admin, payable(seller), address(0), id, address(treasury), FEE_BPS, BIDDING_TIME, REVEAL_TIME, RESERVE
        );
        vm.expectRevert(IBlindAuction.ZeroAddress.selector);
        new BlindAuction(
            admin, payable(seller), address(nft), id, address(0), FEE_BPS, BIDDING_TIME, REVEAL_TIME, RESERVE
        );
        vm.expectRevert(IBlindAuction.InvalidTimes.selector);
        new BlindAuction(admin, payable(seller), address(nft), id, address(treasury), FEE_BPS, 0, REVEAL_TIME, RESERVE);
        vm.expectRevert(IBlindAuction.InvalidTimes.selector);
        new BlindAuction(admin, payable(seller), address(nft), id, address(treasury), FEE_BPS, BIDDING_TIME, 0, RESERVE);
        vm.expectRevert(BlindAuction.InvalidFeeBps.selector);
        new BlindAuction(
            admin, payable(seller), address(nft), id, address(treasury), 1001, BIDDING_TIME, REVEAL_TIME, RESERVE
        );
    }

    function test_PlaceBid_RevertsAtMaxBidsPerAddress() public {
        BlindAuction auction = _deployBlindAuctionDirect();
        vm.deal(buyer, 21 ether);
        vm.startPrank(buyer);
        for (uint256 i; i < 20; ++i) {
            auction.placeBid{ value: 1 ether }(auction.computeBlindedBid(1 ether, false, keccak256(abi.encode(i))));
        }
        bytes32 oneTooMany = auction.computeBlindedBid(1 ether, false, keccak256("one_too_many"));
        vm.expectRevert(abi.encodeWithSelector(IBlindAuction.TooManyBids.selector, 20));
        auction.placeBid{ value: 1 ether }(oneTooMany);
        vm.stopPrank();
    }

    function test_Reveal_RevertsOnArrayLengthMismatch() public {
        BlindAuction auction = _deployBlindAuctionDirect();
        bytes32 blinded = _blindBid(auction, 2 ether, false, keccak256("secret1"));
        vm.deal(buyer, 2 ether);
        vm.prank(buyer);
        auction.placeBid{ value: 2 ether }(blinded);
        vm.warp(block.timestamp + BIDDING_TIME + 1);
        uint256[] memory values = new uint256[](2);
        bool[] memory fakes = new bool[](1);
        bytes32[] memory secrets = new bytes32[](1);
        vm.prank(buyer);
        vm.expectRevert(IBlindAuction.ArrayLengthMismatch.selector);
        auction.reveal(values, fakes, secrets);
    }

    function test_Reveal_UnderfundedBidNeverBecomesHighest() public {
        BlindAuction auction = _deployBlindAuctionDirect();
        bytes32 secret = keccak256("secret1");

        bytes32 blinded = _blindBid(auction, 2 ether, false, secret);
        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        auction.placeBid{ value: 1 ether }(blinded);
        vm.warp(block.timestamp + BIDDING_TIME + 1);
        uint256[] memory values = new uint256[](1);
        values[0] = 2 ether;
        bool[] memory fakes = new bool[](1);
        bytes32[] memory secrets = new bytes32[](1);
        secrets[0] = secret;
        vm.prank(buyer);
        auction.reveal(values, fakes, secrets);
        assertEq(auction.highestBidder(), address(0));
    }

    function test_Reveal_SecondHigherBidOutbidsAndRefundsFirst() public {
        BlindAuction auction = _deployBlindAuctionDirect();
        bytes32 secretA = keccak256("a");
        bytes32 secretB = keccak256("b");
        vm.deal(buyer, 2 ether);
        vm.prank(buyer);
        auction.placeBid{ value: 2 ether }(_blindBid(auction, 2 ether, false, secretA));
        vm.deal(buyer2, 3 ether);
        vm.prank(buyer2);
        auction.placeBid{ value: 3 ether }(_blindBid(auction, 3 ether, false, secretB));
        vm.warp(block.timestamp + BIDDING_TIME + 1);

        uint256[] memory v1 = new uint256[](1);
        v1[0] = 2 ether;
        bool[] memory f1 = new bool[](1);
        bytes32[] memory s1 = new bytes32[](1);
        s1[0] = secretA;
        vm.prank(buyer);
        auction.reveal(v1, f1, s1);

        uint256[] memory v2 = new uint256[](1);
        v2[0] = 3 ether;
        bool[] memory f2 = new bool[](1);
        bytes32[] memory s2 = new bytes32[](1);
        s2[0] = secretB;
        vm.prank(buyer2);
        auction.reveal(v2, f2, s2);

        assertEq(auction.highestBidder(), buyer2);
        assertEq(auction.getPendingReturn(buyer), 2 ether);
    }

    function test_Cancel_RevertsWhenAlreadyEndedOrCancelled() public {
        BlindAuction auction = _deployBlindAuctionDirect();
        vm.warp(block.timestamp + BIDDING_TIME + REVEAL_TIME + 2);
        auction.finalizeAuction();
        vm.prank(admin);
        vm.expectRevert(IBlindAuction.AlreadyFinalized.selector);
        auction.cancelAuction();
    }

    function test_Withdraw_PaysPendingReturnAndRevertsWhenEmpty() public {
        BlindAuction auction = _deployBlindAuctionDirect();
        bytes32 secretA = keccak256("a");
        bytes32 secretB = keccak256("b");
        vm.deal(buyer, 2 ether);
        vm.prank(buyer);
        auction.placeBid{ value: 2 ether }(_blindBid(auction, 2 ether, false, secretA));
        vm.deal(buyer2, 3 ether);
        vm.prank(buyer2);
        auction.placeBid{ value: 3 ether }(_blindBid(auction, 3 ether, false, secretB));
        vm.warp(block.timestamp + BIDDING_TIME + 1);
        uint256[] memory v1 = new uint256[](1);
        v1[0] = 2 ether;
        bool[] memory f1 = new bool[](1);
        bytes32[] memory s1 = new bytes32[](1);
        s1[0] = secretA;
        vm.prank(buyer);
        auction.reveal(v1, f1, s1);
        uint256[] memory v2 = new uint256[](1);
        v2[0] = 3 ether;
        bool[] memory f2 = new bool[](1);
        bytes32[] memory s2 = new bytes32[](1);
        s2[0] = secretB;
        vm.prank(buyer2);
        auction.reveal(v2, f2, s2);

        uint256 before = buyer.balance;
        vm.prank(buyer);
        auction.withdraw();
        assertEq(buyer.balance, before + 2 ether);

        vm.prank(buyer);
        vm.expectRevert(IBlindAuction.NothingToWithdraw.selector);
        auction.withdraw();
    }

    function test_WithdrawIfCancelled_RevertsWhenNothingToWithdraw() public {
        BlindAuction auction = _deployBlindAuctionDirect();
        vm.prank(admin);
        auction.cancelAuction();
        vm.prank(buyer);
        vm.expectRevert(IBlindAuction.NothingToWithdraw.selector);
        auction.withdrawIfCancelled();
    }

    function test_Pause_BlocksBidRevealFinalizeAndWithdraw() public {
        BlindAuction auction = _deployBlindAuctionDirect();
        vm.prank(admin);
        auction.pause();
        bytes32 blinded = _blindBid(auction, 2 ether, false, keccak256("s"));
        vm.deal(buyer, 2 ether);
        vm.prank(buyer);
        vm.expectRevert();
        auction.placeBid{ value: 2 ether }(blinded);

        vm.prank(admin);
        auction.unpause();
        vm.prank(buyer);
        auction.placeBid{ value: 2 ether }(blinded);
    }

    function test_DirectETH_Reverts() public {
        BlindAuction auction = _deployBlindAuctionDirect();
        vm.deal(attacker, 1 ether);
        vm.prank(attacker);
        (bool ok,) = address(auction).call{ value: 1 ether }("");
        assertFalse(ok);
    }

    function _revealOne(BlindAuction auction, address bidder, uint256 value, bool fake, bytes32 secret) internal {
        uint256[] memory values = new uint256[](1);
        bool[] memory fakes = new bool[](1);
        bytes32[] memory secrets = new bytes32[](1);
        values[0] = value;
        fakes[0] = fake;
        secrets[0] = secret;
        vm.prank(bidder);
        auction.reveal(values, fakes, secrets);
    }

    function test_Finalize_ReserveNotMet_RefundsRevealedHighestBidAndReturnsNFT() public {
        BlindAuction auction = _deployBlindAuctionDirect();
        bytes32 secret = keccak256("below-reserve");
        vm.deal(buyer, 0.5 ether);
        vm.prank(buyer);
        auction.placeBid{ value: 0.5 ether }(_blindBid(auction, 0.5 ether, false, secret));
        vm.warp(block.timestamp + BIDDING_TIME + 1);
        _revealOne(auction, buyer, 0.5 ether, false, secret);
        assertEq(auction.highestBidder(), buyer);
        vm.warp(block.timestamp + REVEAL_TIME + 1);
        auction.finalizeAuction();
        assertEq(nft.ownerOf(tokenId), seller);
        assertEq(auction.highestBidder(), address(0));
        assertEq(auction.highestBid(), 0);
        assertEq(auction.getPendingReturn(buyer), 0.5 ether);
        assertEq(treasury.claimable(seller), 0);
        assertTrue(auction.auctionEnded());
        vm.prank(buyer);
        auction.withdraw();
        assertEq(buyer.balance, 0.5 ether);
    }

    function test_Reveal_NearRevealEndExtendsDeadlineUpToTheMaximum() public {
        BlindAuction auction = _deployBlindAuctionDirect();
        address[5] memory bidders = [buyer, makeAddr("late1"), makeAddr("late2"), makeAddr("late3"), makeAddr("late4")];
        bytes32[5] memory secrets;
        for (uint256 i; i < bidders.length; ++i) {
            secrets[i] = keccak256(abi.encodePacked("late-reveal", i));
            bytes32 commitment = _blindBid(auction, 2 ether, false, secrets[i]);
            vm.deal(bidders[i], 2 ether);
            vm.prank(bidders[i]);
            auction.placeBid{ value: 2 ether }(commitment);
        }
        uint256 originalRevealEnd = auction.revealEnd();
        vm.warp(originalRevealEnd - 1 minutes);
        _revealOne(auction, bidders[0], 2 ether, false, secrets[0]);
        assertEq(auction.revealExtensionsUsed(), 1);
        assertEq(auction.revealEnd(), originalRevealEnd + auction.REVEAL_EXTENSION_TIME());
        vm.warp(originalRevealEnd + 1);
        assertEq(uint8(auction.currentPhase()), uint8(IBlindAuction.Phase.Reveal));

        for (uint256 i = 1; i < bidders.length; ++i) {
            vm.warp(auction.revealEnd() - 1 minutes);
            _revealOne(auction, bidders[i], 2 ether, false, secrets[i]);
        }
        assertEq(auction.revealExtensionsUsed(), auction.MAX_REVEAL_EXTENSIONS());
        assertEq(
            auction.revealEnd(), originalRevealEnd + auction.MAX_REVEAL_EXTENSIONS() * auction.REVEAL_EXTENSION_TIME()
        );
        assertEq(auction.highestBid(), 2 ether);
    }

    function test_WithdrawUnrevealed_RevertsBeforeRevealEndAndWhenNothingToWithdraw() public {
        BlindAuction auction = _deployBlindAuctionDirect();
        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        auction.placeBid{ value: 1 ether }(_blindBid(auction, 1 ether, false, keccak256("never-revealed")));
        vm.prank(buyer);
        vm.expectRevert(IBlindAuction.AlreadyFinalized.selector);
        auction.withdrawUnrevealed();
        vm.warp(block.timestamp + BIDDING_TIME + 1);
        vm.prank(buyer);
        vm.expectRevert(IBlindAuction.AlreadyFinalized.selector);
        auction.withdrawUnrevealed();
        vm.warp(block.timestamp + REVEAL_TIME + 1);
        vm.prank(buyer);
        auction.withdrawUnrevealed();
        assertEq(buyer.balance, 1 ether);
        vm.prank(buyer);
        vm.expectRevert(IBlindAuction.NothingToWithdraw.selector);
        auction.withdrawUnrevealed();
        vm.prank(buyer2);
        vm.expectRevert(IBlindAuction.NothingToWithdraw.selector);
        auction.withdrawUnrevealed();
    }

    function test_WithdrawUnrevealed_SkipsRevealedBidsAndRefundsOnlyTheUnrevealedOne() public {
        BlindAuction auction = _deployBlindAuctionDirect();
        bytes32 secretA = keccak256("revealed");
        bytes32 secretB = keccak256("hidden");
        vm.deal(buyer, 3 ether);
        vm.startPrank(buyer);
        auction.placeBid{ value: 2 ether }(_blindBid(auction, 2 ether, false, secretA));
        auction.placeBid{ value: 1 ether }(_blindBid(auction, 1 ether, false, secretB));
        vm.stopPrank();
        vm.warp(block.timestamp + BIDDING_TIME + 1);
        uint256[] memory values = new uint256[](2);
        bool[] memory fakes = new bool[](2);
        bytes32[] memory secrets = new bytes32[](2);
        values[0] = 2 ether;
        values[1] = 1 ether;
        secrets[0] = secretA;
        secrets[1] = keccak256("wrong-secret");
        vm.prank(buyer);
        auction.reveal(values, fakes, secrets);
        assertEq(auction.highestBid(), 2 ether);
        assertEq(auction.totalUnrevealedDeposits(), 1 ether);
        vm.warp(block.timestamp + REVEAL_TIME + 1);
        vm.prank(buyer);
        auction.withdrawUnrevealed();
        assertEq(buyer.balance, 1 ether);
        assertEq(auction.totalUnrevealedDeposits(), 0);
        auction.finalizeAuction();
        assertEq(nft.ownerOf(tokenId), buyer);
    }

    function test_Cancel_RevertsWhenAlreadyCancelled() public {
        BlindAuction auction = _deployBlindAuctionDirect();
        vm.prank(admin);
        auction.cancelAuction();
        vm.prank(admin);
        vm.expectRevert(IBlindAuction.AlreadyFinalized.selector);
        auction.cancelAuction();
    }

    function test_PlaceBid_RevertsInRevealPhaseWithPhaseDetails() public {
        BlindAuction auction = _deployBlindAuctionDirect();
        vm.warp(block.timestamp + BIDDING_TIME + 1);
        bytes32 blinded = auction.computeBlindedBid(1 ether, false, bytes32(uint256(5)));
        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBlindAuction.InvalidPhase.selector, IBlindAuction.Phase.Reveal, IBlindAuction.Phase.Bidding
            )
        );
        auction.placeBid{ value: 1 ether }(blinded);
    }

    function test_Pause_BlocksFinalizeButNeverBlocksWithdrawals() public {
        BlindAuction auction = _deployBlindAuctionDirect();
        bytes32 secretA = keccak256("a-paused");
        bytes32 secretB = keccak256("b-paused");
        vm.deal(buyer, 2 ether);
        vm.prank(buyer);
        auction.placeBid{ value: 2 ether }(_blindBid(auction, 2 ether, false, secretA));
        vm.deal(buyer2, 3 ether);
        vm.prank(buyer2);
        auction.placeBid{ value: 3 ether }(_blindBid(auction, 3 ether, false, secretB));
        vm.deal(attacker, 1 ether);
        vm.prank(attacker);
        auction.placeBid{ value: 1 ether }(_blindBid(auction, 1 ether, false, keccak256("unrevealed-paused")));
        vm.warp(block.timestamp + BIDDING_TIME + 1);
        _revealOne(auction, buyer, 2 ether, false, secretA);
        _revealOne(auction, buyer2, 3 ether, false, secretB);
        vm.warp(block.timestamp + REVEAL_TIME + 1);
        vm.prank(admin);
        auction.pause();
        vm.expectRevert();
        auction.finalizeAuction();
        vm.prank(buyer);
        auction.withdraw();
        assertEq(buyer.balance, 2 ether);
        vm.prank(attacker);
        auction.withdrawUnrevealed();
        assertEq(attacker.balance, 1 ether);
        vm.prank(admin);
        auction.unpause();
        auction.finalizeAuction();
        assertEq(nft.ownerOf(tokenId), buyer2);
    }

    function test_Constructor_RejectsNonContractNFTAndTreasury() public {
        uint256 id = _mint(nft, seller);
        vm.expectRevert(IBlindAuction.ZeroAddress.selector);
        new BlindAuction(
            admin, payable(seller), address(0xBEEF), id, address(treasury), FEE_BPS, BIDDING_TIME, REVEAL_TIME, RESERVE
        );
        vm.expectRevert(IBlindAuction.ZeroAddress.selector);
        new BlindAuction(
            admin, payable(seller), address(nft), id, address(0xBEEF), FEE_BPS, BIDDING_TIME, REVEAL_TIME, RESERVE
        );
    }

    function test_Reveal_ByAddressWithoutBidsCannotExtendTheDeadline() public {
        BlindAuction auction = _deployBlindAuctionDirect();
        vm.warp(auction.revealEnd() - 1 minutes);
        uint256 revealEndBefore = auction.revealEnd();
        uint256[] memory values = new uint256[](0);
        bool[] memory fakes = new bool[](0);
        bytes32[] memory secrets = new bytes32[](0);
        vm.prank(attacker);
        auction.reveal(values, fakes, secrets);
        assertEq(auction.revealExtensionsUsed(), 0);
        assertEq(auction.revealEnd(), revealEndBefore);
    }
}

contract BlindAuctionLiabilityTest is ProtocolTestBase {
    function test_UnrevealedDepositsAreTrackedUntilRecovery() public {
        _setUpCore();
        uint256 tokenId = _mint(nft, seller);
        BlindAuction auction = new BlindAuction(
            admin, payable(seller), address(nft), tokenId, address(treasury), FEE_BPS, 1 days, 1 days, 1 ether
        );
        vm.prank(seller);
        nft.approve(address(this), tokenId);
        vm.prank(seller);
        nft.transferFrom(seller, address(auction), tokenId);

        bytes32 blinded = auction.computeBlindedBid(2 ether, false, keccak256("unrevealed"));
        vm.deal(buyer, 2 ether);
        vm.prank(buyer);
        auction.placeBid{ value: 2 ether }(blinded);

        assertEq(auction.totalUnrevealedDeposits(), 2 ether);
        assertEq(address(auction).balance, auction.totalUnrevealedDeposits());

        vm.warp(block.timestamp + 2 days + 1);
        auction.finalizeAuction();
        vm.prank(buyer);
        auction.withdrawUnrevealed();

        assertEq(auction.totalUnrevealedDeposits(), 0);
        assertEq(address(auction).balance, auction.totalPendingReturns());
    }
}

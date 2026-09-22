pragma solidity ^0.8.24;
import "../helpers/TestBase.sol";
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
        return auction.computeBlindedBid(value, fake, secret);
    }
    function setUp() public {
        _setUpCore();
    }
    function test_PlaceBid_DuringBiddingPhase() public {
        BlindAuction auction = _deployBlindAuctionDirect();
        bytes32 blinded = _blindBid(auction, 2 ether, false, keccak256("secret1"));
        vm.deal(buyer, 2 ether);
        vm.prank(buyer);
        auction.placeBid{value: 2 ether}(blinded);
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
        auction.placeBid{value: 2 ether}(blinded);
    }
    function test_PlaceBid_RevertsOutsideBiddingPhase() public {
        BlindAuction auction = _deployBlindAuctionDirect();
        vm.warp(block.timestamp + BIDDING_TIME + 1);
        bytes32 blinded = _blindBid(auction, 2 ether, false, keccak256("secret1"));
        vm.deal(buyer, 2 ether);
        vm.prank(buyer);
        vm.expectRevert();
        auction.placeBid{value: 2 ether}(blinded);
    }
    function test_Reveal_HonestBidBecomesHighest() public {
        BlindAuction auction = _deployBlindAuctionDirect();
        bytes32 secret = keccak256("secret1");
        bytes32 blinded = _blindBid(auction, 2 ether, false, secret);
        vm.deal(buyer, 2 ether);
        vm.prank(buyer);
        auction.placeBid{value: 2 ether}(blinded);
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
        auction.placeBid{value: 3 ether}(blinded); 
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
    function test_Reveal_MismatchedRevealIsSilentlyIgnored_DepositStaysLocked() public {
        BlindAuction auction = _deployBlindAuctionDirect();
        bytes32 secret = keccak256("secret1");
        bytes32 blinded = _blindBid(auction, 2 ether, false, secret);
        vm.deal(buyer, 2 ether);
        vm.prank(buyer);
        auction.placeBid{value: 2 ether}(blinded);
        vm.warp(block.timestamp + BIDDING_TIME + 1);
        uint256[] memory values = new uint256[](1);
        values[0] = 999 ether; 
        bool[] memory fakes = new bool[](1);
        fakes[0] = false;
        bytes32[] memory secrets = new bytes32[](1);
        secrets[0] = secret;
        vm.prank(buyer);
        auction.reveal(values, fakes, secrets);
        assertEq(auction.getPendingReturn(buyer), 0, "a mismatched reveal is not auto-refunded");
    }
    function test_Finalize_ReserveMet_PaysSellerAndReleasesNFT() public {
        BlindAuction auction = _deployBlindAuctionDirect();
        bytes32 secret = keccak256("secret1");
        bytes32 blinded = _blindBid(auction, 2 ether, false, secret);
        vm.deal(buyer, 2 ether);
        vm.prank(buyer);
        auction.placeBid{value: 2 ether}(blinded);
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
        auction.placeBid{value: 2 ether}(blinded);
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
        auction.placeBid{value: 2 ether}(blinded); 
        vm.prank(admin);
        auction.cancelAuction();
        uint256 before = buyer.balance;
        vm.prank(buyer);
        auction.withdrawIfCancelled();
        assertEq(buyer.balance, before + 2 ether);
    }
}

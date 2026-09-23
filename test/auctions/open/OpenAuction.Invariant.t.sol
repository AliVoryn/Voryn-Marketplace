// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import "forge-std/StdInvariant.sol";
import "../../support/TestBase.sol";

contract OpenAuctionHandler is Test {
    OpenAuction public auctionHouse;
    CustomNFT public nft;
    address public admin;
    address public seller;
    address[] public bidders;
    uint256 public activeAuctionId;

    constructor(OpenAuction _auctionHouse, CustomNFT _nft, address _admin, address _seller, address[] memory _bidders) {
        auctionHouse = _auctionHouse;
        nft = _nft;
        admin = _admin;
        seller = _seller;
        bidders = _bidders;
    }

    function createNewAuction(uint64 durationSeed) external {
        if (activeAuctionId != 0) {
            IAuction.Auction memory current = auctionHouse.getAuction(activeAuctionId);
            bool terminal = current.phase == IAuction.Phase.Finalized || current.phase == IAuction.Phase.Failed
                || current.phase == IAuction.Phase.Cancelled;
            if (!terminal) return;
        }
        vm.prank(admin);
        uint256 tokenId = nft.mint(seller, "ipfs://token");
        vm.prank(seller);
        nft.approve(address(auctionHouse), tokenId);
        uint64 duration = uint64(bound(durationSeed, 1 hours, 30 days));
        vm.prank(seller);
        try auctionHouse.createAuction(address(nft), tokenId, 1 ether, 0.1 ether, 0, duration) returns (uint256 newId) {
            activeAuctionId = newId;
        } catch { }
    }

    function placeBid(uint256 bidderSeed, uint256 amountSeed) external {
        if (activeAuctionId == 0) return;
        address bidder = bidders[bidderSeed % bidders.length];
        IAuction.Auction memory a = auctionHouse.getAuction(activeAuctionId);
        if (a.phase != IAuction.Phase.Active && a.phase != IAuction.Phase.Created) return;
        if (block.timestamp >= a.endAt) return;
        uint256 minimum = a.highestBid == 0 ? a.reservePrice : a.highestBid + a.minIncrement;
        uint256 amount = bound(amountSeed, minimum, minimum + 10 ether);
        vm.deal(bidder, amount);
        vm.prank(bidder);
        try auctionHouse.placeBid{ value: amount }(activeAuctionId) { } catch { }
    }

    function withdrawRefund(uint256 bidderSeed) external {
        address bidder = bidders[bidderSeed % bidders.length];
        if (auctionHouse.getRefund(bidder) == 0) return;
        vm.prank(bidder);
        try auctionHouse.withdrawRefund() { } catch { }
    }

    function finalize() external {
        if (activeAuctionId == 0) return;
        IAuction.Auction memory a = auctionHouse.getAuction(activeAuctionId);
        if (block.timestamp < a.endAt) return;
        try auctionHouse.finalizeAuction(activeAuctionId) { } catch { }
    }

    function cancel() external {
        if (activeAuctionId == 0) return;
        vm.prank(seller);
        try auctionHouse.cancelAuction(activeAuctionId) { } catch { }
    }

    function warp(uint256 secondsSeed) external {
        vm.warp(block.timestamp + bound(secondsSeed, 1, 2 days));
    }
}

contract OpenAuctionInvariantTest is ProtocolTestBase {
    OpenAuction internal auctionHouse;
    OpenAuctionHandler internal handler;

    function setUp() public {
        _setUpCore();
        auctionHouse = _deployOpenAuction(address(treasury));
        vm.prank(admin);
        treasury.setAuthorizedPayer(address(auctionHouse), true);
        address[] memory bidderSet = new address[](3);
        bidderSet[0] = buyer;
        bidderSet[1] = buyer2;
        bidderSet[2] = attacker;
        handler = new OpenAuctionHandler(auctionHouse, nft, admin, seller, bidderSet);
        targetContract(address(handler));
    }

    function invariant_EscrowNeverInsolvent() public view {
        assertGe(
            address(auctionHouse).balance, auctionHouse.totalActiveBidLiability() + auctionHouse.totalRefundLiability()
        );
    }
}

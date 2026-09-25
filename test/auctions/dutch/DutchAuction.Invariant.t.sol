// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../../support/TestBase.sol";

contract DutchAuctionHandler is Test {
    DutchAuction internal house;
    CustomNFT internal nft;
    address internal admin;
    address internal seller;
    address[3] internal buyers;

    uint256[] public auctionIds;
    uint256 public totalPaid;

    constructor(DutchAuction house_, CustomNFT nft_, address admin_, address seller_, address[3] memory buyers_) {
        house = house_;
        nft = nft_;
        admin = admin_;
        seller = seller_;
        buyers = buyers_;
    }

    function idCount() external view returns (uint256) {
        return auctionIds.length;
    }

    function createAuction(uint256 startPriceSeed, uint256 durationSeed) external {
        uint256 startPrice = bound(startPriceSeed, 2 ether, 10 ether);
        uint64 duration = uint64(bound(durationSeed, 1 hours, 10 days));
        vm.prank(admin);
        uint256 tokenId = nft.mint(seller, "ipfs://dutch");
        vm.prank(seller);
        nft.approve(address(house), tokenId);
        vm.prank(seller);
        uint256 id = house.createAuction(address(nft), tokenId, startPrice, startPrice / 2, 0, duration);
        auctionIds.push(id);
    }

    function buy(uint256 idSeed, uint256 buyerSeed, uint256 overpaySeed) external {
        if (auctionIds.length == 0) return;
        uint256 id = auctionIds[idSeed % auctionIds.length];
        address buyer = buyers[buyerSeed % buyers.length];
        uint256 price;
        try house.currentPrice(id) returns (uint256 current) {
            price = current;
        } catch {
            return;
        }
        uint256 overpay = bound(overpaySeed, 0, 1 ether);
        vm.deal(buyer, price + overpay);
        vm.prank(buyer);
        try house.buy{ value: price + overpay }(id) {
            totalPaid += price;
        } catch { }
    }

    function cancel(uint256 idSeed) external {
        if (auctionIds.length == 0) return;
        vm.prank(seller);
        try house.cancelAuction(auctionIds[idSeed % auctionIds.length]) { } catch { }
    }

    function expire(uint256 idSeed) external {
        if (auctionIds.length == 0) return;
        try house.expireAuction(auctionIds[idSeed % auctionIds.length]) { } catch { }
    }

    function warp(uint256 secondsSeed) external {
        vm.warp(block.timestamp + bound(secondsSeed, 1, 3 days));
    }
}

contract DutchAuctionInvariantTest is ProtocolTestBase {
    DutchAuction internal house;
    DutchAuctionHandler internal handler;

    function setUp() public {
        _setUpCore();
        house = _deployDutchAuction(address(treasury));
        vm.prank(admin);
        treasury.setAuthorizedPayer(address(house), true);
        address[3] memory buyers = [buyer, buyer2, attacker];
        handler = new DutchAuctionHandler(house, nft, admin, seller, buyers);
        targetContract(address(handler));
    }

    function invariant_EveryTokenIsHeldByTheRightParty() public view {
        uint256 count = handler.idCount();
        for (uint256 i; i < count; ++i) {
            IDutchAuction.Auction memory auction = house.getAuction(handler.auctionIds(i));
            address holder = nft.ownerOf(auction.tokenId);
            if (
                auction.status == IDutchAuction.AuctionStatus.Created
                    || auction.status == IDutchAuction.AuctionStatus.Active
            ) {
                assertEq(holder, address(house));
            } else if (auction.status == IDutchAuction.AuctionStatus.Sold) {
                assertEq(holder, auction.buyer);
            } else {
                assertEq(holder, auction.seller);
            }
        }
    }

    function invariant_SettlementCreditsEqualPricesPaidAndAuctionKeepsNoEth() public view {
        assertEq(treasury.totalLiabilities(), handler.totalPaid());
        assertEq(address(house).balance, 0);
        assertEq(address(treasury).balance, handler.totalPaid());
    }
}

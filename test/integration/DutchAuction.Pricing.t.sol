pragma solidity ^0.8.24;
import "../helpers/TestBase.sol";
contract DutchAuctionPricingTest is ProtocolTestBase {
    DutchAuction internal house;
    uint256 internal tokenId;
    uint64 internal constant DURATION = 1000;
    function setUp() public {
        _setUpCore();
        house = _deployDutchAuction(address(treasury));
        vm.prank(admin);
        treasury.setAuthorizedPayer(address(house), true);
        tokenId = _mint(nft, seller);
        vm.prank(seller);
        nft.approve(address(house), tokenId);
    }
    function _create() internal returns (uint256 auctionId) {
        vm.prank(seller);
        auctionId = house.createAuction(address(nft), tokenId, 10 ether, 1 ether, 0, DURATION);
    }
    function test_Price_AtStart_EqualsStartPrice() public {
        uint256 auctionId = _create();
        assertEq(house.currentPrice(auctionId), 10 ether);
    }
    function test_Price_AtMidpoint_IsHalfwayBetween() public {
        uint256 auctionId = _create();
        vm.warp(block.timestamp + DURATION / 2);
        assertEq(house.currentPrice(auctionId), 5.5 ether);
    }
    function test_FINDING_EndPriceIsAsymptoticFloor_NeverActuallyPurchasable() public {
        uint256 auctionId = _create();
        vm.warp(block.timestamp + DURATION - 1);
        uint256 priceOneSecondBeforeEnd = house.currentPrice(auctionId);
        assertGt(priceOneSecondBeforeEnd, 1 ether, "price must still be above endPrice one second before endAt");
        vm.warp(block.timestamp + 1); 
        assertEq(house.currentPrice(auctionId), 1 ether, "currentPrice() view DOES report endPrice at/after endAt");
        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        vm.expectRevert(IDutchAuction.InvalidPhase.selector);
        house.buy{value: 1 ether}(auctionId); 
    }
    function test_Buy_AtExactCurrentPrice_Succeeds() public {
        uint256 auctionId = _create();
        vm.warp(block.timestamp + DURATION / 2);
        uint256 price = house.currentPrice(auctionId);
        vm.deal(buyer, price);
        vm.prank(buyer);
        house.buy{value: price}(auctionId);
        assertEq(nft.ownerOf(tokenId), buyer);
        (uint256 fee, uint256 sellerAmount) = _split(price);
        assertEq(treasury.claimable(seller), sellerAmount);
        assertEq(treasury.claimable(feeRecipient), fee);
    }
    function test_Buy_WrongPayment_Reverts() public {
        uint256 auctionId = _create();
        vm.deal(buyer, 20 ether);
        vm.prank(buyer);
        vm.expectRevert(IDutchAuction.PaymentMismatch.selector);
        house.buy{value: 9 ether}(auctionId); 
    }
    function test_Expire_AfterEndAt_ReturnsNFT() public {
        uint256 auctionId = _create();
        vm.warp(block.timestamp + DURATION);
        house.expireAuction(auctionId);
        assertEq(nft.ownerOf(tokenId), seller);
    }
    function test_Cancel_BeforeEndAt_ReturnsNFT() public {
        uint256 auctionId = _create();
        vm.prank(seller);
        house.cancelAuction(auctionId);
        assertEq(nft.ownerOf(tokenId), seller);
    }
    function _split(uint256 amount) internal pure returns (uint256 fee, uint256 sellerAmount) {
        fee = amount * 250 / 10_000;
        sellerAmount = amount - fee;
    }
}

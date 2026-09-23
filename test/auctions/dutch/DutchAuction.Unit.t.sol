// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import "../../support/TestBase.sol";

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

    function test_Buy_OneSecondBeforeEndAt_Succeeds() public {
        uint256 auctionId = _create();
        vm.warp(block.timestamp + DURATION - 1);
        uint256 price = house.currentPrice(auctionId);
        assertGe(price, 1 ether);
        vm.deal(buyer, price);
        vm.prank(buyer);
        house.buy{ value: price }(auctionId);
        assertEq(nft.ownerOf(tokenId), buyer);
    }

    function test_Buy_AtExactCurrentPrice_Succeeds() public {
        uint256 auctionId = _create();
        vm.warp(block.timestamp + DURATION / 2);
        uint256 price = house.currentPrice(auctionId);
        vm.deal(buyer, price);
        vm.prank(buyer);
        house.buy{ value: price }(auctionId);
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
        house.buy{ value: 9 ether }(auctionId);
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

    function test_Constructor_RevertsForZeroTreasuryAndTooHighFee() public {
        vm.expectRevert(IDutchAuction.ZeroAddress.selector);
        new DutchAuction(admin, address(0), FEE_BPS);
        vm.expectRevert(IDutchAuction.FeeTooHigh.selector);
        new DutchAuction(admin, address(treasury), 1001);
    }

    function test_CreateAuction_RevertsOnEachInvalidInput() public {
        vm.startPrank(seller);
        vm.expectRevert(IDutchAuction.ZeroAddress.selector);
        house.createAuction(address(0), tokenId, 10 ether, 1 ether, 0, DURATION);

        vm.expectRevert(IDutchAuction.InvalidPriceRange.selector);
        house.createAuction(address(nft), tokenId, 0, 1 ether, 0, DURATION);

        vm.expectRevert(IDutchAuction.InvalidPriceRange.selector);
        house.createAuction(address(nft), tokenId, 10 ether, 0, 0, DURATION);

        vm.expectRevert(IDutchAuction.InvalidPriceRange.selector);
        house.createAuction(address(nft), tokenId, 1 ether, 1 ether, 0, DURATION);

        vm.expectRevert(IDutchAuction.InvalidTime.selector);
        house.createAuction(address(nft), tokenId, 10 ether, 1 ether, 0, 0);

        vm.warp(block.timestamp + 1);
        vm.expectRevert(IDutchAuction.InvalidTime.selector);
        house.createAuction(address(nft), tokenId, 10 ether, 1 ether, uint64(block.timestamp - 1), DURATION);
        vm.stopPrank();

        vm.prank(buyer);
        vm.expectRevert(IDutchAuction.NotSeller.selector);
        house.createAuction(address(nft), tokenId, 10 ether, 1 ether, 0, DURATION);
    }

    function test_CreateAuction_FutureStartLeavesStatusCreated() public {
        uint64 startAt = uint64(block.timestamp + 100);
        vm.prank(seller);
        uint256 auctionId = house.createAuction(address(nft), tokenId, 10 ether, 1 ether, startAt, DURATION);
        IDutchAuction.Auction memory auction = house.getAuction(auctionId);
        assertEq(uint8(auction.status), uint8(IDutchAuction.AuctionStatus.Created));
    }

    function test_Buy_RevertsBeforeStart() public {
        uint64 startAt = uint64(block.timestamp + 100);
        vm.prank(seller);
        uint256 auctionId = house.createAuction(address(nft), tokenId, 10 ether, 1 ether, startAt, DURATION);
        vm.deal(buyer, 10 ether);
        vm.prank(buyer);
        vm.expectRevert(IDutchAuction.InvalidPhase.selector);
        house.buy{ value: 10 ether }(auctionId);
    }

    function test_Buy_RevertsForInvalidAuctionId() public {
        vm.expectRevert(IDutchAuction.InvalidAuction.selector);
        house.buy(999);
    }

    function test_Buy_ActivatesFromCreatedWhenStartReached() public {
        uint64 startAt = uint64(block.timestamp + 100);
        vm.prank(seller);
        uint256 auctionId = house.createAuction(address(nft), tokenId, 10 ether, 1 ether, startAt, DURATION);
        vm.warp(startAt);
        uint256 price = house.currentPrice(auctionId);
        vm.deal(buyer, price);
        vm.prank(buyer);
        house.buy{ value: price }(auctionId);
        assertEq(nft.ownerOf(tokenId), buyer);
    }

    function test_Buy_RevertsWhenAlreadySold() public {
        uint256 auctionId = _create();
        uint256 price = house.currentPrice(auctionId);
        vm.deal(buyer, price);
        vm.prank(buyer);
        house.buy{ value: price }(auctionId);

        vm.deal(buyer2, price);
        vm.prank(buyer2);
        vm.expectRevert(IDutchAuction.InvalidPhase.selector);
        house.buy{ value: price }(auctionId);
    }

    function test_Buy_ZeroFeeWhenProtocolFeeBpsIsZero() public {
        DutchAuction zeroFeeHouse = new DutchAuction(admin, address(treasury), 0);
        vm.prank(admin);
        treasury.setAuthorizedPayer(address(zeroFeeHouse), true);
        uint256 id = _mint(nft, seller);
        vm.prank(seller);
        nft.approve(address(zeroFeeHouse), id);
        vm.prank(seller);
        uint256 auctionId = zeroFeeHouse.createAuction(address(nft), id, 10 ether, 1 ether, 0, DURATION);
        vm.deal(buyer, 10 ether);
        vm.prank(buyer);
        zeroFeeHouse.buy{ value: 10 ether }(auctionId);
        assertEq(treasury.claimable(feeRecipient), 0);
        assertEq(treasury.claimable(seller), 10 ether);
    }

    function test_Cancel_RevertsForInvalidIdUnauthorizedAndWrongStatus() public {
        vm.expectRevert(IDutchAuction.InvalidAuction.selector);
        house.cancelAuction(999);

        uint256 auctionId = _create();
        vm.prank(attacker);
        vm.expectRevert(IDutchAuction.NotSeller.selector);
        house.cancelAuction(auctionId);

        vm.prank(admin);
        house.cancelAuction(auctionId);
        assertEq(nft.ownerOf(tokenId), seller);

        vm.prank(seller);
        vm.expectRevert(IDutchAuction.InvalidPhase.selector);
        house.cancelAuction(auctionId);
    }

    function test_Cancel_RevertsAfterEndAt() public {
        uint256 auctionId = _create();
        vm.warp(block.timestamp + DURATION);
        vm.prank(seller);
        vm.expectRevert(IDutchAuction.InvalidPhase.selector);
        house.cancelAuction(auctionId);
    }

    function test_Expire_RevertsForInvalidIdWrongStatusAndTooEarly() public {
        vm.expectRevert(IDutchAuction.InvalidAuction.selector);
        house.expireAuction(999);

        uint256 auctionId = _create();
        vm.expectRevert(IDutchAuction.InvalidTime.selector);
        house.expireAuction(auctionId);

        vm.warp(block.timestamp + DURATION);
        house.expireAuction(auctionId);

        vm.expectRevert(IDutchAuction.InvalidPhase.selector);
        house.expireAuction(auctionId);
    }

    function test_CurrentPriceAndGetAuction_RevertForInvalidId() public {
        vm.expectRevert(IDutchAuction.InvalidAuction.selector);
        house.currentPrice(999);
        vm.expectRevert(IDutchAuction.InvalidAuction.selector);
        house.getAuction(999);
    }

    function test_Pause_BlocksAllStateChangingActions() public {
        uint256 auctionId = _create();
        vm.prank(admin);
        house.pause();

        vm.prank(seller);
        vm.expectRevert();
        house.createAuction(address(nft), tokenId, 10 ether, 1 ether, 0, DURATION);

        vm.deal(buyer, 10 ether);
        vm.prank(buyer);
        vm.expectRevert();
        house.buy{ value: 10 ether }(auctionId);

        vm.prank(seller);
        vm.expectRevert();
        house.cancelAuction(auctionId);

        vm.prank(admin);
        house.unpause();
        vm.prank(seller);
        house.cancelAuction(auctionId);
    }

    function test_DirectETH_Reverts() public {
        vm.deal(attacker, 1 ether);
        vm.prank(attacker);
        (bool ok,) = address(house).call{ value: 1 ether }("");
        assertFalse(ok);
    }

    function test_AuctionCount_TracksCreatedAuctions() public {
        assertEq(house.auctionCount(), 0);
        _create();
        assertEq(house.auctionCount(), 1);
    }

    function test_Buy_RevertsAtExactEndAt() public {
        uint256 auctionId = _create();
        vm.warp(block.timestamp + DURATION);
        vm.deal(buyer, 10 ether);
        vm.prank(buyer);
        vm.expectRevert(IDutchAuction.InvalidPhase.selector);
        house.buy{ value: 10 ether }(auctionId);
        assertEq(nft.ownerOf(tokenId), address(house));
    }

    function test_Buy_RevertsAfterEndAt() public {
        uint256 auctionId = _create();
        vm.warp(block.timestamp + DURATION + 1);
        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        vm.expectRevert(IDutchAuction.InvalidPhase.selector);
        house.buy{ value: 1 ether }(auctionId);
    }

    function test_Buy_OverpaymentIsRefundedAndOnlyCurrentPriceIsCharged() public {
        uint256 auctionId = _create();
        vm.warp(block.timestamp + DURATION / 2);
        uint256 price = house.currentPrice(auctionId);
        assertEq(price, 5.5 ether);
        vm.deal(buyer, 10 ether);
        vm.prank(buyer);
        house.buy{ value: 10 ether }(auctionId);
        (uint256 fee, uint256 sellerAmount) = _split(price);
        assertEq(buyer.balance, 10 ether - price);
        assertEq(house.getAuction(auctionId).soldPrice, price);
        assertEq(treasury.claimable(feeRecipient), fee);
        assertEq(treasury.claimable(seller), sellerAmount);
        assertEq(address(house).balance, 0);
        assertEq(nft.ownerOf(tokenId), buyer);
    }

    function test_Buy_RevertsWhenBuyerCannotReceiveTheOverpaymentRefund() public {
        uint256 auctionId = _create();
        RejectingDutchBuyer rejecting = new RejectingDutchBuyer();
        vm.deal(address(rejecting), 20 ether);
        vm.expectRevert(IDutchAuction.RefundFailed.selector);
        rejecting.buy(house, auctionId, 20 ether);
        assertEq(nft.ownerOf(tokenId), address(house));
        rejecting.buy(house, auctionId, 10 ether);
        assertEq(nft.ownerOf(tokenId), address(rejecting));
    }

    function test_Expire_WorksFromCreatedStatusAfterScheduledWindowPasses() public {
        uint64 startAt = uint64(block.timestamp + 100);
        vm.prank(seller);
        uint256 auctionId = house.createAuction(address(nft), tokenId, 10 ether, 1 ether, startAt, DURATION);
        vm.warp(startAt + DURATION);
        house.expireAuction(auctionId);
        assertEq(uint8(house.getAuction(auctionId).status), uint8(IDutchAuction.AuctionStatus.Expired));
        assertEq(nft.ownerOf(tokenId), seller);
    }

    function test_Cancel_WorksFromCreatedStatusBeforeScheduledStart() public {
        uint64 startAt = uint64(block.timestamp + 100);
        vm.prank(seller);
        uint256 auctionId = house.createAuction(address(nft), tokenId, 10 ether, 1 ether, startAt, DURATION);
        vm.prank(seller);
        house.cancelAuction(auctionId);
        assertEq(uint8(house.getAuction(auctionId).status), uint8(IDutchAuction.AuctionStatus.Cancelled));
        assertEq(nft.ownerOf(tokenId), seller);
    }
}

contract RejectingDutchBuyer {
    function buy(DutchAuction house, uint256 auctionId, uint256 value) external {
        house.buy{ value: value }(auctionId);
    }

    receive() external payable {
        revert();
    }
}

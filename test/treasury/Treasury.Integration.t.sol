// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../support/TestBase.sol";

contract TreasuryIntegrationTest is ProtocolTestBase {
    Marketplace internal marketplace;
    Staking internal staking;

    function setUp() public {
        _setUpCore();
        marketplace = _deployMarketplaceProxy(address(treasury), address(paymentManager));
        staking = _deployStaking(address(treasury));
        vm.startPrank(admin);
        treasury.setAuthorizedPayer(address(marketplace), true);
        treasury.setAuthorizedPayer(address(staking), true);
        vm.stopPrank();
    }

    function _sell(uint256 price) internal {
        uint256 tokenId = _mint(nft, seller);
        vm.prank(seller);
        nft.approve(address(marketplace), tokenId);
        vm.prank(seller);
        uint256 listingId = marketplace.createListing(address(nft), tokenId, price, 0);
        vm.deal(buyer, price);
        vm.prank(buyer);
        marketplace.buy{ value: price }(listingId);
    }

    function test_FeeRecipientRotationAffectsOnlyFutureFees() public {
        address nextRecipient = makeAddr("nextFeeRecipient");
        _sell(1 ether);
        assertEq(treasury.claimable(feeRecipient), 0.025 ether);

        vm.prank(admin);
        treasury.setFeeRecipient(nextRecipient);
        _sell(2 ether);

        assertEq(treasury.claimable(feeRecipient), 0.025 ether);
        assertEq(treasury.claimable(nextRecipient), 0.05 ether);
        assertEq(treasury.totalLiabilities(), 3 ether);
        assertEq(address(treasury).balance, treasury.totalLiabilities());
    }

    function test_ClaimantsWithdrawExactlyTheirShareAndLiabilitiesShrink() public {
        _sell(1 ether);
        uint256 sellerBefore = seller.balance;
        vm.prank(seller);
        treasury.withdrawClaimable();
        assertEq(seller.balance, sellerBefore + 0.975 ether);
        assertEq(treasury.totalLiabilities(), 0.025 ether);
        vm.prank(feeRecipient);
        treasury.withdrawClaimable();
        assertEq(treasury.totalLiabilities(), 0);
        assertEq(address(treasury).balance, 0);
    }

    function test_SpendingLimitBoundsStakingRewardFundingFromTreasury() public {
        vm.deal(address(this), 5 ether);
        (bool success,) = address(treasury).call{ value: 5 ether }("");
        assertTrue(success);
        vm.prank(admin);
        treasury.setSpendingLimit(address(staking), 1 ether);
        assertEq(treasury.spendingLimitOf(address(staking)), 1 ether);

        vm.prank(admin);
        staking.fundRewardsFromTreasury(1 ether);
        vm.prank(admin);
        vm.expectRevert(ITreasury.DailyLimitExceeded.selector);
        staking.fundRewardsFromTreasury(1 wei);

        vm.warp(block.timestamp + 1 days);
        vm.prank(admin);
        staking.fundRewardsFromTreasury(1 ether);
        assertEq(staking.rewardReserve(), 2 ether);
        assertEq(treasury.availableBalance(), 3 ether);
    }

    function test_RevokedPayerCanNoLongerCreditOrPay() public {
        _sell(1 ether);
        vm.prank(admin);
        treasury.setAuthorizedPayer(address(marketplace), false);
        uint256 tokenId = _mint(nft, seller);
        vm.prank(seller);
        nft.approve(address(marketplace), tokenId);
        vm.prank(seller);
        uint256 listingId = marketplace.createListing(address(nft), tokenId, 1 ether, 0);
        vm.deal(buyer2, 1 ether);
        vm.prank(buyer2);
        vm.expectRevert(ITreasury.Unauthorized.selector);
        marketplace.buy{ value: 1 ether }(listingId);
        assertEq(nft.ownerOf(tokenId), seller);
    }
}

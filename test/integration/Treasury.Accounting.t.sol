pragma solidity ^0.8.24;
import "../helpers/TestBase.sol";
contract RejectingRecipient {
    receive() external payable { revert(); }
}
contract TreasuryAccountingTest is ProtocolTestBase {
    function setUp() public {
        _setUpCore();
    }
    function test_regression_SetProtocolFeeBps_RevertsWithInvalidFeeBps_NotUnauthorized() public {
        vm.prank(admin);
        vm.expectRevert(ITreasury.InvalidFeeBps.selector);
        treasury.setProtocolFeeBps(1001);
    }
    function test_Credit_RevertsForUnauthorizedPayer() public {
        vm.deal(attacker, 1 ether);
        vm.prank(attacker);
        vm.expectRevert(ITreasury.Unauthorized.selector);
        treasury.credit{value: 1 ether}(buyer, keccak256("X"));
    }
    function test_TreasuryConfigurationRejectsUnauthorizedAndZeroAddresses() public {
        vm.prank(attacker);
        vm.expectRevert();
        treasury.setAuthorizedPayer(buyer, true);
        vm.prank(admin);
        vm.expectRevert(ITreasury.ZeroAddress.selector);
        treasury.setAuthorizedPayer(address(0), true);
        vm.prank(admin);
        vm.expectRevert(ITreasury.ZeroAddress.selector);
        treasury.setFeeRecipient(address(0));
        vm.prank(admin);
        treasury.setFeeRecipient(buyer);
        assertEq(treasury.feeRecipientForProtocol(), buyer);
    }
    function test_Credit_IncreasesClaimableAndLiabilities() public {
        vm.deal(admin, 1 ether);
        vm.prank(admin);
        treasury.credit{value: 1 ether}(seller, keccak256("SALE"));
        assertEq(treasury.claimable(seller), 1 ether);
        assertEq(treasury.totalLiabilities(), 1 ether);
    }
    function testFuzz_Invariant_BalanceNeverBelowLiabilities(uint96 amount1, uint96 amount2) public {
        vm.deal(admin, uint256(amount1) + uint256(amount2));
        vm.startPrank(admin);
        if (amount1 > 0) treasury.credit{value: amount1}(seller, keccak256("A"));
        if (amount2 > 0) treasury.credit{value: amount2}(buyer, keccak256("B"));
        vm.stopPrank();
        assertGe(address(treasury).balance, treasury.totalLiabilities());
        uint256 sellerClaimable = treasury.claimable(seller);
        vm.prank(seller);
        if (sellerClaimable > 0) treasury.withdrawClaimable();
        assertGe(address(treasury).balance, treasury.totalLiabilities());
    }
    function test_WithdrawClaimable_RevertsWhenNothingClaimable() public {
        vm.prank(buyer);
        vm.expectRevert(ITreasury.InsufficientAvailableBalance.selector);
        treasury.withdrawClaimable();
    }
    function test_WithdrawClaimable_ZeroesOutBalanceAndPays() public {
        vm.deal(admin, 1 ether);
        vm.prank(admin);
        treasury.credit{value: 1 ether}(seller, keccak256("SALE"));
        uint256 before = seller.balance;
        vm.prank(seller);
        treasury.withdrawClaimable();
        assertEq(seller.balance, before + 1 ether);
        assertEq(treasury.claimable(seller), 0);
        assertEq(treasury.totalLiabilities(), 0);
    }
    function test_Pay_RespectsAvailableBalance_NotJustRawBalance() public {
        vm.deal(admin, 1 ether);
        vm.prank(admin);
        treasury.credit{value: 1 ether}(seller, keccak256("SALE"));
        assertEq(treasury.availableBalance(), 0);
        vm.prank(admin);
        vm.expectRevert(ITreasury.InsufficientAvailableBalance.selector);
        treasury.pay(payable(buyer), 1 ether, keccak256("REWARD_FUNDING"));
    }
    function test_Pay_SucceedsFromDirectlyDonatedFunds() public {
        vm.deal(address(this), 1 ether);
        (bool ok,) = address(treasury).call{value: 1 ether}("");
        assertTrue(ok);
        assertEq(treasury.availableBalance(), 1 ether);
        vm.prank(admin);
        treasury.pay(payable(buyer), 1 ether, keccak256("REWARD_FUNDING"));
        assertEq(buyer.balance, 1 ether);
    }
    function test_PayAndRescueRejectZeroAndFailedRecipients() public {
        vm.deal(address(this), 2 ether);
        (bool ok,) = address(treasury).call{value: 2 ether}("");
        assertTrue(ok);
        RejectingRecipient rejecting = new RejectingRecipient();
        vm.prank(admin);
        vm.expectRevert(ITreasury.ZeroAddress.selector);
        treasury.pay(payable(address(0)), 1 ether, keccak256("X"));
        vm.prank(admin);
        vm.expectRevert(ITreasury.PaymentFailed.selector);
        treasury.pay(payable(address(rejecting)), 1 ether, keccak256("X"));
        vm.prank(admin);
        vm.expectRevert(ITreasury.ZeroAddress.selector);
        treasury.emergencyRescue(payable(address(0)), 1 ether);
        vm.prank(admin);
        vm.expectRevert(ITreasury.NoRescueBalance.selector);
        treasury.emergencyRescue(payable(buyer), 3 ether);
        vm.prank(admin);
        vm.expectRevert(ITreasury.PaymentFailed.selector);
        treasury.emergencyRescue(payable(address(rejecting)), 1 ether);
    }
    function test_RemainingAllowanceCoversUnlimitedSpentAndResetBranches() public {
        assertEq(treasury.remainingDailyAllowance(admin), type(uint256).max);
        vm.prank(admin);
        treasury.setSpendingLimit(admin, 1 ether);
        assertEq(treasury.spendingLimitOf(admin), 1 ether);
        vm.deal(address(this), 2 ether);
        (bool ok,) = address(treasury).call{value: 2 ether}("");
        assertTrue(ok);
        vm.prank(admin);
        treasury.pay(payable(buyer), 1 ether, keccak256("X"));
        assertEq(treasury.remainingDailyAllowance(admin), 0);
        vm.warp(block.timestamp + 1 days);
        assertEq(treasury.remainingDailyAllowance(admin), 1 ether);
    }
    function test_Pay_RespectsDailySpendingLimit() public {
        vm.deal(address(this), 10 ether);
        (bool ok,) = address(treasury).call{value: 10 ether}("");
        assertTrue(ok);
        vm.prank(admin);
        treasury.setSpendingLimit(admin, 1 ether);
        vm.prank(admin);
        treasury.pay(payable(buyer), 1 ether, keccak256("X")); 
        vm.prank(admin);
        vm.expectRevert(ITreasury.DailyLimitExceeded.selector);
        treasury.pay(payable(buyer), 1 wei, keccak256("X")); 
    }
    function test_Pay_DailyLimitResetsAfterOneDay() public {
        vm.deal(address(this), 10 ether);
        (bool ok,) = address(treasury).call{value: 10 ether}("");
        assertTrue(ok);
        vm.prank(admin);
        treasury.setSpendingLimit(admin, 1 ether);
        vm.prank(admin);
        treasury.pay(payable(buyer), 1 ether, keccak256("X"));
        vm.warp(block.timestamp + 1 days);
        vm.prank(admin);
        treasury.pay(payable(buyer), 1 ether, keccak256("X")); 
    }
}

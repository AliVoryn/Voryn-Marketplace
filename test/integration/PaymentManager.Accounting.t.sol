pragma solidity ^0.8.24;
import "../helpers/TestBase.sol";
contract PaymentManagerAccountingTest is ProtocolTestBase {
    function setUp() public {
        _setUpCore();
        vm.prank(admin);
        paymentManager.setCreditor(admin, true);
    }
    function test_Credit_RevertsForUnauthorizedCreditor() public {
        vm.deal(attacker, 1 ether);
        vm.prank(attacker);
        vm.expectRevert(); 
        paymentManager.credit{value: 1 ether}(buyer, keccak256("REFUND"));
    }
    function test_Credit_Accumulates() public {
        vm.deal(admin, 2 ether);
        vm.startPrank(admin);
        paymentManager.credit{value: 1 ether}(buyer, keccak256("A"));
        paymentManager.credit{value: 1 ether}(buyer, keccak256("B"));
        vm.stopPrank();
        assertEq(paymentManager.claimable(buyer), 2 ether);
        assertEq(paymentManager.totalClaimable(), 2 ether);
    }
    function test_Withdraw_PaysExactClaimableAndZeroesIt() public {
        vm.deal(admin, 1 ether);
        vm.prank(admin);
        paymentManager.credit{value: 1 ether}(buyer, keccak256("REFUND"));
        uint256 before = buyer.balance;
        vm.prank(buyer);
        paymentManager.withdraw();
        assertEq(buyer.balance, before + 1 ether);
        assertEq(paymentManager.claimable(buyer), 0);
        assertEq(paymentManager.totalClaimable(), 0);
    }
    function test_Withdraw_RevertsWhenNothingClaimable() public {
        vm.prank(buyer);
        vm.expectRevert(IPaymentManager.NothingToWithdraw.selector);
        paymentManager.withdraw();
    }
    function testFuzz_Invariant_BalanceCoversAggregateClaimable(uint96 a1, uint96 a2) public {
        vm.deal(admin, uint256(a1) + uint256(a2));
        vm.startPrank(admin);
        if (a1 > 0) paymentManager.credit{value: a1}(buyer, keccak256("A"));
        if (a2 > 0) paymentManager.credit{value: a2}(buyer2, keccak256("B"));
        vm.stopPrank();
        uint256 aggregateClaimable = paymentManager.claimable(buyer) + paymentManager.claimable(buyer2);
        assertGe(address(paymentManager).balance, aggregateClaimable);
    }
    function test_DirectETH_Reverts() public {
        vm.deal(attacker, 1 ether);
        vm.prank(attacker);
        (bool ok,) = address(paymentManager).call{value: 1 ether}("");
        assertFalse(ok, "direct ETH transfers must be rejected");
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import "forge-std/Test.sol";
import "../../src/libraries/FeeMath.sol";

contract FeeMathHarness {
    function fee(uint256 amount, uint16 bps) external pure returns (uint256) {
        return FeeMath.fee(amount, bps);
    }
}

contract FeeMathTest is Test {
    FeeMathHarness internal harness;

    function setUp() public {
        harness = new FeeMathHarness();
    }

    function test_fee_ZeroBpsIsZero() public pure {
        assertEq(FeeMath.fee(1 ether, 0), 0);
    }

    function test_fee_MaxBpsIsFullAmount() public pure {
        assertEq(FeeMath.fee(1 ether, 10_000), 1 ether);
    }

    function test_fee_RevertsAboveMaxBps() public {
        vm.expectRevert(FeeMath.FeeTooHigh.selector);
        harness.fee(1 ether, 10_001);
    }

    function test_split_SumsBackToAmount(uint256 amount, uint16 bps) public pure {
        amount = bound(amount, 0, 1_000_000_000 ether);
        bps = uint16(bound(bps, 0, 10_000));
        (uint256 protocolFee, uint256 sellerAmount) = FeeMath.split(amount, bps);
        assertEq(protocolFee + sellerAmount, amount, "fee split must conserve the input amount exactly");
    }

    function test_split_250Bps() public pure {
        (uint256 protocolFee, uint256 sellerAmount) = FeeMath.split(1 ether, 250);
        assertEq(protocolFee, 0.025 ether);
        assertEq(sellerAmount, 0.975 ether);
    }

    function testFuzz_split_ProtocolFeeNeverExceedsExactShare(uint128 amount, uint16 bps) public pure {
        bps = uint16(bound(bps, 0, 10_000));
        (uint256 protocolFee,) = FeeMath.split(amount, bps);
        assertLe(protocolFee * 10_000, uint256(amount) * bps + 9_999);
    }
}

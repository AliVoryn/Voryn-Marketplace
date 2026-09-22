// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import "forge-std/StdInvariant.sol";

import "../support/TestBase.sol";

contract TreasuryInvariantHandler is Test {
    Treasury internal treasury;

    receive() external payable { }

    constructor(Treasury treasury_) {
        treasury = treasury_;
    }

    function creditSelf(uint256 amountSeed) external {
        uint256 amount = bound(amountSeed, 1 wei, 5 ether);
        vm.deal(address(this), amount);
        treasury.credit{ value: amount }(address(this), keccak256("INVARIANT_CREDIT"));
    }

    function withdrawSelf() external {
        if (treasury.claimable(address(this)) == 0) return;
        treasury.withdrawClaimable();
    }

    function donate(uint256 amountSeed) external {
        uint256 amount = bound(amountSeed, 1 wei, 5 ether);
        vm.deal(address(this), amount);
        (bool success,) = address(treasury).call{ value: amount }("");
        if (!success) revert();
    }

    function paySelf(uint256 amountSeed) external {
        uint256 amount = bound(amountSeed, 1 wei, 5 ether);
        try treasury.pay(payable(address(this)), amount, keccak256("INVARIANT_PAYMENT")) { } catch { }
    }
}

contract TreasuryInvariantTest is ProtocolTestBase {
    TreasuryInvariantHandler internal handler;

    function setUp() public {
        treasury = _deployTreasury();
        handler = new TreasuryInvariantHandler(treasury);
        vm.prank(admin);
        treasury.setAuthorizedPayer(address(handler), true);
        targetContract(address(handler));
    }

    function invariant_TreasuryLiabilitiesNeverExceedBalance() public view {
        assertGe(address(treasury).balance, treasury.totalLiabilities());
    }
}

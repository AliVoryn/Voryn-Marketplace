// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/StdInvariant.sol";
import "forge-std/Test.sol";
import "../../src/core/PaymentManager.sol";

contract PaymentManagerInvariantHandler {
    PaymentManager internal immutable manager;

    constructor(PaymentManager manager_) {
        manager = manager_;
    }

    function credit(uint256 amount, bytes32 reason) external {
        amount = (amount % 10 ether) + 1;
        manager.credit{ value: amount }(address(this), reason);
    }

    function withdraw() external {
        if (manager.claimable(address(this)) != 0) {
            manager.withdraw();
        }
    }

    receive() external payable { }
}

contract PaymentManagerInvariantTest is Test {
    PaymentManager internal manager;
    PaymentManagerInvariantHandler internal handler;

    function setUp() public {
        manager = new PaymentManager(address(this), address(this));
        handler = new PaymentManagerInvariantHandler(manager);
        manager.setCreditor(address(handler), true);
        vm.deal(address(handler), 100 ether);
        targetContract(address(handler));
    }

    function invariant_TotalClaimableEqualsKnownClaim() public view {
        assertEq(manager.totalClaimable(), manager.claimable(address(handler)));
        assertLe(manager.totalClaimable(), address(manager).balance);
    }
}

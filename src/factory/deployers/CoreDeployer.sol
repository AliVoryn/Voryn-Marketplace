// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../../core/Treasury.sol";
import "../../core/PaymentManager.sol";

library CoreDeployer {
    function deployTreasury(address initialOwner, address feeRecipient, address factoryController)
        external
        returns (address)
    {
        return address(new Treasury(initialOwner, feeRecipient, factoryController));
    }

    function deployPaymentManager(address initialOwner, address factoryController) external returns (address) {
        return address(new PaymentManager(initialOwner, factoryController));
    }

    function deployProxy(address implementation, bytes memory initData) external returns (address) {
        return address(new ERC1967Proxy(implementation, initData));
    }
}

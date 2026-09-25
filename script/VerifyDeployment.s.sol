// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import { Ownable2Step } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { ProtocolFactory } from "../src/factory/ProtocolFactory.sol";
import { ProtocolRegistry } from "../src/registries/ProtocolRegistry.sol";
import { Treasury } from "../src/core/Treasury.sol";
import { PaymentManager } from "../src/core/PaymentManager.sol";

interface IMarketplaceAuthority {
    function hasRole(bytes32 role, address account) external view returns (bool);
    function DEFAULT_ADMIN_ROLE() external view returns (bytes32);
    function OPERATOR_ROLE() external view returns (bytes32);
    function treasury() external view returns (address);
    function paymentManager() external view returns (address);
}

interface IRegistryState {
    function registrar(address account) external view returns (bool);
}

contract VerifyDeploymentScript is Script {
    error DeploymentMismatch(bytes32 check);

    function run() external view {
        ProtocolFactory factory = ProtocolFactory(vm.envAddress("FACTORY_ADDRESS"));
        ProtocolRegistry registry = factory.registry();
        address admin = vm.envAddress("PROTOCOL_ADMIN");
        address treasury = vm.envAddress("TREASURY_ADDRESS");
        address paymentManager = vm.envAddress("PAYMENT_MANAGER_ADDRESS");
        address timelock = vm.envAddress("GOVERNANCE_TIMELOCK");
        address marketplace = vm.envAddress("MARKETPLACE_ADDRESS");

        if (admin == address(0) || timelock == address(0) || marketplace == address(0)) {
            revert DeploymentMismatch("zero-config");
        }
        if (admin != timelock) revert DeploymentMismatch("admin-timelock");
        if (factory.owner() != admin) revert DeploymentMismatch("factory-owner");
        if (registry.owner() != admin) revert DeploymentMismatch("registry-owner");
        if (Treasury(payable(treasury)).owner() != admin) revert DeploymentMismatch("treasury-owner");
        if (PaymentManager(payable(paymentManager)).owner() != admin) revert DeploymentMismatch("payment-owner");
        if (Treasury(payable(treasury)).feeRecipient() != vm.envAddress("FEE_RECIPIENT")) {
            revert DeploymentMismatch("fee-recipient");
        }
        if (!IRegistryState(address(registry)).registrar(address(factory))) {
            revert DeploymentMismatch("factory-registrar");
        }
        if (Treasury(payable(treasury)).factoryController() != address(0)) {
            revert DeploymentMismatch("treasury-controller");
        }
        if (PaymentManager(payable(paymentManager)).factoryController() != address(0)) {
            revert DeploymentMismatch("payment-controller");
        }
        address openAuction = vm.envAddress("OPEN_AUCTION_ADDRESS");
        address blindAuction = vm.envOr("BLIND_AUCTION_ADDRESS", address(0));
        address dutchAuction = vm.envAddress("DUTCH_AUCTION_ADDRESS");
        address staking = vm.envAddress("STAKING_ADDRESS");
        if (!Treasury(payable(treasury)).authorizedPayer(marketplace)) revert DeploymentMismatch("marketplace-payer");
        if (!Treasury(payable(treasury)).authorizedPayer(openAuction)) revert DeploymentMismatch("open-auction-payer");
        if (blindAuction != address(0) && !Treasury(payable(treasury)).authorizedPayer(blindAuction)) {
            revert DeploymentMismatch("blind-auction-payer");
        }
        if (!Treasury(payable(treasury)).authorizedPayer(dutchAuction)) {
            revert DeploymentMismatch("dutch-auction-payer");
        }
        if (!Treasury(payable(treasury)).authorizedPayer(staking)) revert DeploymentMismatch("staking-payer");
        if (!PaymentManager(payable(paymentManager)).authorizedCreditor(marketplace)) {
            revert DeploymentMismatch("marketplace-creditor");
        }
        if (Ownable2Step(openAuction).owner() != timelock) revert DeploymentMismatch("open-auction-owner");
        if (blindAuction != address(0) && Ownable2Step(blindAuction).owner() != timelock) {
            revert DeploymentMismatch("blind-auction-owner");
        }
        if (Ownable2Step(dutchAuction).owner() != timelock) revert DeploymentMismatch("dutch-auction-owner");
        if (Ownable2Step(staking).owner() != timelock) revert DeploymentMismatch("staking-owner");
        bytes32 defaultAdmin = IMarketplaceAuthority(marketplace).DEFAULT_ADMIN_ROLE();
        bytes32 operatorRole = IMarketplaceAuthority(marketplace).OPERATOR_ROLE();
        if (!IMarketplaceAuthority(marketplace).hasRole(defaultAdmin, timelock)) {
            revert DeploymentMismatch("marketplace-governance");
        }
        address operator = vm.envOr("GOVERNANCE_OPERATOR", address(0));
        if (operator != address(0) && !IMarketplaceAuthority(marketplace).hasRole(operatorRole, operator)) {
            revert DeploymentMismatch("marketplace-operator");
        }
        if (IMarketplaceAuthority(marketplace).treasury() != treasury) {
            revert DeploymentMismatch("marketplace-treasury");
        }
        if (IMarketplaceAuthority(marketplace).paymentManager() != paymentManager) {
            revert DeploymentMismatch("marketplace-payment-manager");
        }
        address raffle = vm.envOr("RAFFLE_ADDRESS", address(0));
        if (raffle != address(0) && Ownable2Step(raffle).owner() != timelock) {
            revert DeploymentMismatch("raffle-owner");
        }
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import "@openzeppelin/contracts/access/Ownable2Step.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { IPaymentManager } from "../interfaces/IPaymentManager.sol";

contract PaymentManager is Ownable2Step, ReentrancyGuard, IPaymentManager {
    mapping(address => uint256) private claimableBalance;
    mapping(address => bool) public override authorizedCreditor;
    uint256 public totalClaimable;
    address public override factoryController;

    constructor(address initialOwner, address factoryController_) Ownable(initialOwner) {
        factoryController = factoryController_;
    }
    modifier onlyCreditor() {
        if (!authorizedCreditor[msg.sender]) revert Unauthorized();
        _;
    }

    function setFactoryController(address controller) external override onlyOwner {
        factoryController = controller;
        emit FactoryControllerUpdated(controller);
    }

    function setCreditor(address creditor, bool authorized) external override {
        if (msg.sender != owner() && msg.sender != factoryController) revert Unauthorized();
        if (creditor == address(0)) revert ZeroAddress();
        authorizedCreditor[creditor] = authorized;
        emit CreditorAuthorizationChanged(creditor, authorized);
    }

    function credit(address account, bytes32 reason) external payable override onlyCreditor {
        if (account == address(0)) revert ZeroAddress();
        if (msg.value == 0) revert ZeroAmount();
        claimableBalance[account] += msg.value;
        totalClaimable += msg.value;
        emit PaymentCredited(account, msg.value, reason);
    }

    function withdraw() external override nonReentrant {
        uint256 amount = claimableBalance[msg.sender];
        if (amount == 0) revert NothingToWithdraw();
        claimableBalance[msg.sender] = 0;
        totalClaimable -= amount;
        (bool success,) = payable(msg.sender).call{ value: amount }("");
        if (!success) revert PaymentFailed();
        emit PaymentWithdrawn(msg.sender, amount);
    }

    function claimable(address account) external view override returns (uint256) {
        return claimableBalance[account];
    }

    receive() external payable {
        revert DirectPaymentNotAllowed();
    }
}

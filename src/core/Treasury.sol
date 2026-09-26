// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import "@openzeppelin/contracts/access/Ownable2Step.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { ITreasury } from "../interfaces/ITreasury.sol";
import { AccountingMath } from "../libraries/AccountingMath.sol";

contract Treasury is Ownable2Step, ReentrancyGuard, ITreasury {
    struct SpendingWindow {
        uint256 limit;
        uint256 spent;
        uint256 windowStartedAt;
    }
    mapping(address => uint256) private claimableBalance;
    mapping(address => bool) public override authorizedPayer;
    mapping(address => SpendingWindow) private spendingWindows;
    uint256 public totalLiabilities;
    address public feeRecipient;
    address public override factoryController;

    constructor(address initialOwner, address initialFeeRecipient, address factoryController_) Ownable(initialOwner) {
        if (initialFeeRecipient == address(0)) revert ZeroAddress();
        factoryController = factoryController_;
        feeRecipient = initialFeeRecipient;
    }
    modifier onlyAuthorizedPayer() {
        if (!authorizedPayer[msg.sender]) revert Unauthorized();
        _;
    }

    function setFactoryController(address controller) external override onlyOwner {
        factoryController = controller;
        emit FactoryControllerUpdated(controller);
    }

    function setAuthorizedPayer(address payer, bool allowed) external override {
        if (msg.sender != owner() && msg.sender != factoryController) revert Unauthorized();
        if (payer == address(0)) revert ZeroAddress();
        authorizedPayer[payer] = allowed;
        emit PayerAuthorizationChanged(payer, allowed);
    }

    function setFeeRecipient(address recipient) external onlyOwner {
        if (recipient == address(0)) revert ZeroAddress();
        address previousRecipient = feeRecipient;
        feeRecipient = recipient;
        emit FeeRecipientUpdated(previousRecipient, recipient);
    }

    function feeRecipientForProtocol() external view override returns (address) {
        return feeRecipient;
    }

    function credit(address account, bytes32 reason) external payable override onlyAuthorizedPayer {
        if (account == address(0)) revert ZeroAddress();
        if (msg.value == 0) revert ZeroAmount();
        claimableBalance[account] += msg.value;
        totalLiabilities += msg.value;
        emit Credit(account, msg.value, reason);
    }

    function pay(address payable recipient, uint256 amount, bytes32 reason)
        external
        override
        onlyAuthorizedPayer
        nonReentrant
    {
        if (recipient == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();
        _consumeDailyAllowance(msg.sender, amount);
        if (amount > availableBalance()) revert InsufficientAvailableBalance();
        (bool success,) = recipient.call{ value: amount }("");
        if (!success) revert PaymentFailed();
        emit Payment(recipient, amount, reason);
    }

    function claimable(address account) external view override returns (uint256) {
        return claimableBalance[account];
    }

    function withdrawClaimable() external override nonReentrant {
        uint256 amount = claimableBalance[msg.sender];
        if (amount == 0) revert InsufficientAvailableBalance();
        claimableBalance[msg.sender] = 0;
        totalLiabilities -= amount;
        (bool success,) = payable(msg.sender).call{ value: amount }("");
        if (!success) revert PaymentFailed();
        emit Payment(msg.sender, amount, keccak256("CLAIM"));
    }

    function setSpendingLimit(address payer, uint256 dailyLimit) external override onlyOwner {
        if (payer == address(0)) revert ZeroAddress();
        SpendingWindow storage window = spendingWindows[payer];
        window.limit = dailyLimit;
        window.spent = 0;
        window.windowStartedAt = block.timestamp;
        emit SpendingLimitChanged(payer, dailyLimit);
    }

    function spendingLimitOf(address payer) external view override returns (uint256) {
        return spendingWindows[payer].limit;
    }

    function remainingDailyAllowance(address payer) external view override returns (uint256) {
        SpendingWindow memory window = spendingWindows[payer];
        if (window.limit == 0) {
            return type(uint256).max;
        }
        if (window.windowStartedAt == 0 || block.timestamp - window.windowStartedAt >= 1 days) {
            return window.limit;
        }
        if (window.spent >= window.limit) {
            return 0;
        }
        return window.limit - window.spent;
    }

    function availableBalance() public view override returns (uint256) {
        return AccountingMath.available(address(this).balance, totalLiabilities);
    }

    function emergencyRescue(address payable recipient, uint256 amount) external onlyOwner nonReentrant {
        if (recipient == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();
        if (amount > availableBalance()) revert NoRescueBalance();
        (bool success,) = recipient.call{ value: amount }("");
        if (!success) revert PaymentFailed();
        emit EmergencyRescue(recipient, amount);
    }

    function _consumeDailyAllowance(address payer, uint256 amount) internal {
        SpendingWindow storage window = spendingWindows[payer];
        if (window.limit == 0) return;
        if (window.windowStartedAt == 0 || block.timestamp - window.windowStartedAt >= 1 days) {
            window.windowStartedAt = block.timestamp;
            window.spent = 0;
        }
        if (window.spent + amount > window.limit) revert DailyLimitExceeded();
        window.spent += amount;
    }
    receive() external payable { }
}

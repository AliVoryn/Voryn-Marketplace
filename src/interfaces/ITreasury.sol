// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface ITreasury {
    event Credit(address indexed account, uint256 amount, bytes32 indexed reason);
    event Payment(address indexed recipient, uint256 amount, bytes32 indexed reason);
    event FeeRecipientUpdated(address indexed previousRecipient, address indexed newRecipient);
    event PayerAuthorizationChanged(address indexed payer, bool authorized);
    event SpendingLimitChanged(address indexed payer, uint256 dailyLimit);
    event FactoryControllerUpdated(address indexed controller);
    event EmergencyRescue(address indexed recipient, uint256 amount);
    error ZeroAddress();
    error Unauthorized();
    error InsufficientAvailableBalance();
    error PaymentFailed();
    error DailyLimitExceeded();
    error NoRescueBalance();
    error ZeroAmount();
    function credit(address account, bytes32 reason) external payable;
    function pay(address payable recipient, uint256 amount, bytes32 reason) external;
    function availableBalance() external view returns (uint256);
    function claimable(address account) external view returns (uint256);
    function withdrawClaimable() external;
    function setFactoryController(address controller) external;
    function setAuthorizedPayer(address payer, bool allowed) external;
    function authorizedPayer(address payer) external view returns (bool);
    function setSpendingLimit(address payer, uint256 dailyLimit) external;
    function spendingLimitOf(address payer) external view returns (uint256);
    function remainingDailyAllowance(address payer) external view returns (uint256);
    function feeRecipientForProtocol() external view returns (address);
    function factoryController() external view returns (address);
}

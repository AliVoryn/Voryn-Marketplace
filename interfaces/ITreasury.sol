// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface ITreasury {
    event Credit(address indexed account, uint amount, bytes32 indexed reason);
    event Payment(address indexed recipient, uint amount, bytes32 indexed reason);
    event TreasuryConfigurationUpdated(address indexed paymentManager, address indexed feeRecipient);
    event PayerAuthorizationChanged(address indexed payer ,bool authorized) ;
    event SpendingLimitChanged(address indexed payer , uint dailyLimit) ;
    event EmergencyRescue(address indexed recipient , uint amount);
    event ProtocolFeeUpdated(uint16 bps);
    

    error ZeroAddress();
    error Unauthorized();
    error InsufficientAvailableBalance();
    error PaymentFailed();
    error DailyLimitExceeded();
    error NoRescueBalance();

    function credit(address account, bytes32 reason) external payable;
    function pay(address payable recipient, uint amount, bytes32 reason) external;
    function availableBalance() external view returns (uint);
    function claimable(address account) external view returns (uint);
    function withdrawClaimable() external;
    function setSpendingLimit(address payer, uint dailyLimit) external;
    function spendingLimitOf(address payer) external view returns (uint);
    function remainingDailyAllowance(address payer) external view returns (uint);
    function feeRecipientForProtocol() external view returns (address);
}

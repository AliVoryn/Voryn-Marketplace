// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Address.sol";

import "../interfaces/ITreasury.sol";
import "../libraries/AccountingMath.sol";

contract Treasury is Ownable2Step, ReentrancyGuard, ITreasury {
    using Address for address payable;

    struct SpendingWindow {
        uint limit;
        uint spent;
        uint64 windowStartedAt;
    }

    mapping(address => uint) private claimableBalance;
    mapping(address => bool) public authorizedPayer;
    mapping(address => SpendingWindow) private spendingWindows;

    uint public totalLiabilities;

    address public feeRecipient;
    uint16 public protocolFeeBps = 250;

    constructor(address initialOwner,address initialFeeRecipient) Ownable(initialOwner) {
        if (initialFeeRecipient ==address(0)) revert ZeroAddress();
        feeRecipient = initialFeeRecipient;
    }

    modifier onlyAuthorizedPayer() {
        if (!authorizedPayer[msg.sender]) revert Unauthorized();
        
        _;
    }

    function setAuthorizedPayer(address payer,bool allowed) external onlyOwner {
        if (payer == address(0)) revert ZeroAddress();
        
        authorizedPayer[payer] = allowed;
        emit PayerAuthorizationChanged(payer,allowed);
    }

    function setProtocolFeeBps(uint16 bps) external onlyOwner {
        if (bps > 1000) revert Unauthorized();
        protocolFeeBps = bps;
        emit ProtocolFeeUpdated(bps);
    }

    function setFeeRecipient(address recipient) external onlyOwner{
        if (recipient == address(0)) revert ZeroAddress();
        feeRecipient = recipient;

        emit TreasuryConfigurationUpdated(address(0),recipient);
    }

    function feeRecipientForProtocol() external view override returns (address)
    {
        return feeRecipient;
    }

    function credit(address account,bytes32 reason) external payable override onlyAuthorizedPayer{
        if (account == address(0)) revert ZeroAddress();

        if (msg.value == 0) revert InsufficientAvailableBalance();
        
        claimableBalance[account] += msg.value;

        totalLiabilities += msg.value;

        emit Credit(account,msg.value,reason);
    }

    function pay( address payable recipient, uint amount, bytes32 reason) external override onlyAuthorizedPayer nonReentrant{
        if (recipient == address(0)) revert ZeroAddress();
        _consumeDailyAllowance(msg.sender,amount);

        if (amount >availableBalance()) revert InsufficientAvailableBalance();
        

        recipient.sendValue(amount);

        emit Payment(recipient,amount,reason);
    }

    function claimable(address account) external view override returns (uint) {
        return claimableBalance[account];
    }

    function withdrawClaimable() external override nonReentrant
    {
        uint amount = claimableBalance[msg.sender];

        if (amount == 0) revert InsufficientAvailableBalance();
        

        claimableBalance[msg.sender] = 0;

        totalLiabilities -= amount;

        payable(msg.sender).sendValue(amount);

        emit Payment(msg.sender,amount,keccak256("CLAIM"));
    }

    function setSpendingLimit(address payer,uint dailyLimit) external override onlyOwner {
        if (payer == address(0)) revert ZeroAddress();
        

        spendingWindows[payer].limit = dailyLimit;

        emit SpendingLimitChanged(payer,dailyLimit);
    }

    function spendingLimitOf(address payer) external view override returns (uint)
    {
        return spendingWindows[payer].limit;
    }

    function remainingDailyAllowance(address payer) external view override returns (uint) {
        SpendingWindow memory window = spendingWindows[payer];

        if (window.limit == 0) {
            return type(uint).max;
        }

        if (block.timestamp >=window.windowStartedAt + 1 days) {
            return window.limit;
        }

        if (window.spent >=window.limit) {
            return 0;
        }

        return window.limit - window.spent;
    }

    function availableBalance() public view override returns (uint)
    {
        return AccountingMath.available(address(this).balance,totalLiabilities);
    }

    function emergencyRescue(address payable recipient,uint amount) external onlyOwner nonReentrant {
        if (recipient == address(0)) revert ZeroAddress();
        

        if (amount >availableBalance()) revert NoRescueBalance();
        

        recipient.sendValue(amount);

        emit EmergencyRescue(recipient,amount);
    }

    function _consumeDailyAllowance(address payer,uint amount)internal
    {
        SpendingWindow storage window = spendingWindows[payer];

        if (window.limit == 0) return;
        

        if (block.timestamp >= window.windowStartedAt + 1 days) {
            window.windowStartedAt = uint64(block.timestamp);
            window.spent = 0;
        }

        if (window.spent + amount >window.limit) revert DailyLimitExceeded();
        
        window.spent += amount;
    }

    receive() external payable {}
}

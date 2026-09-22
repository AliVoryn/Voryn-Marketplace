// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Address.sol";

import "../interfaces/IPaymentManager.sol";

contract PaymentManager is Ownable2Step, ReentrancyGuard, IPaymentManager {
    using Address for address payable;

    mapping(address => uint) private claimableBalance;
    mapping(address => bool) public authorizedCreditor;

    uint public totalClaimable;

    event CreditorAuthorizationChanged(address indexed creditor,bool authorized);

    constructor(address initialOwner) Ownable(initialOwner){}

    modifier onlyCreditor() {
        if (!authorizedCreditor[msg.sender]) revert PaymentFailed();
        
        _;
    }

    function setCreditor(address creditor,bool authorized) external onlyOwner {
        if (creditor == address(0)) revert PaymentFailed();
        
        authorizedCreditor[creditor] = authorized;

        emit CreditorAuthorizationChanged(creditor,authorized);
    }

    function credit(address account,bytes32 reason) external payable override onlyCreditor {
        if (account == address(0)) revert PaymentFailed();
        
        if (msg.value == 0) revert PaymentFailed();

        claimableBalance[account] += msg.value;

        totalClaimable += msg.value;

        emit PaymentCredited(account,msg.value,reason);
    }

    function withdraw() external override nonReentrant{
        uint amount = claimableBalance[msg.sender];

        if (amount == 0) revert NothingToWithdraw();
        

        claimableBalance[msg.sender] = 0;
        totalClaimable -= amount;

        payable(msg.sender).sendValue(amount);

        emit PaymentWithdrawn(msg.sender,amount);
    }

    function claimable(address account) external view override returns (uint)
    {
        return claimableBalance[account];
    }

    receive() external payable {}
}

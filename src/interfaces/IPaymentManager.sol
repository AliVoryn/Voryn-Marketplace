// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IPaymentManager {
    event PaymentCredited(address indexed account, uint256 amount, bytes32 indexed reason);
    event PaymentWithdrawn(address indexed account, uint256 amount);
    event CreditorAuthorizationChanged(address indexed creditor, bool authorized);
    event FactoryControllerUpdated(address indexed controller);
    error NothingToWithdraw();
    error PaymentFailed();
    error Unauthorized();
    error ZeroAddress();
    error ZeroAmount();
    error DirectPaymentNotAllowed();
    function credit(address account, bytes32 reason) external payable;
    function withdraw() external;
    function claimable(address account) external view returns (uint256);
    function setFactoryController(address controller) external;
    function setCreditor(address creditor, bool authorized) external;
    function authorizedCreditor(address creditor) external view returns (bool);
    function factoryController() external view returns (address);
}

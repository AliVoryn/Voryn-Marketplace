pragma solidity ^0.8.24;
interface IPaymentManager {
    event PaymentCredited(address indexed account, uint amount, bytes32 indexed reason);
    event PaymentWithdrawn(address indexed account, uint amount);
    error NothingToWithdraw();
    error PaymentFailed();
    error DirectPaymentNotAllowed();
    function credit(address account, bytes32 reason) external payable;
    function withdraw() external;
    function claimable(address account) external view returns (uint);
}

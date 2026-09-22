pragma solidity ^0.8.24;
interface IUpgradeableSystem {
    event UpgradedByProtocol(address indexed implementation, address indexed authorizedBy);
    function initialize(
        address admin,
        address treasury,
        address paymentManager
    ) external;
    function version() external view returns (uint64);
}

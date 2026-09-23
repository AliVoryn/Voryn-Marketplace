// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IRegistry {
    struct Record {
        address instance;
        address implementation;
        address creator;
        bytes32 kind;
        uint64 version;
        bool active;
    }
    event Registered(
        address indexed instance, bytes32 indexed kind, address indexed creator, address implementation, uint64 version
    );
    event ActivationChanged(address indexed instance, bool active);
    error AlreadyRegistered();
    error UnknownInstance();
    error ZeroAddress();
    function registerInstance(address instance, address creator, address implementation, bytes32 kind, uint64 version)
        external;
    function setActive(address instance, bool active) external;
    function getRecord(address instance) external view returns (Record memory);
    function isRegistered(address instance) external view returns (bool);
}

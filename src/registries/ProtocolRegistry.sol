// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import "@openzeppelin/contracts/access/Ownable2Step.sol";
import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import { IRegistry } from "../interfaces/IRegistry.sol";

contract ProtocolRegistry is Ownable2Step, IRegistry {
    using EnumerableSet for EnumerableSet.AddressSet;
    mapping(address => Record) private records;
    mapping(bytes32 => EnumerableSet.AddressSet) private byKind;
    mapping(address => EnumerableSet.AddressSet) private byCreator;
    EnumerableSet.AddressSet private allInstances;
    mapping(address => bool) public registrar;
    error UnauthorizedRegistrar();
    error InvalidInstance();
    error InvalidCreator();
    error InvalidImplementation();
    error InvalidVersion();
    constructor(address initialOwner) Ownable(initialOwner) { }
    modifier onlyRegistrar() {
        if (!_isAuthorizedRegistrar(msg.sender)) revert UnauthorizedRegistrar();
        _;
    }
    event RegistrarUpdated(address indexed account, bool allowed);

    function setRegistrar(address account, bool allowed) external onlyOwner {
        if (account == address(0)) revert ZeroAddress();
        registrar[account] = allowed;
        emit RegistrarUpdated(account, allowed);
    }

    function _isAuthorizedRegistrar(address account) internal view returns (bool) {
        return account == owner() || registrar[account];
    }

    function registerInstance(address instance, address creator, address implementation, bytes32 kind, uint64 version)
        external
        override
        onlyRegistrar
    {
        if (instance == address(0) || instance.code.length == 0) revert InvalidInstance();
        if (creator == address(0)) revert InvalidCreator();
        if (implementation != address(0) && implementation.code.length == 0) revert InvalidImplementation();
        if (version == 0) revert InvalidVersion();
        if (records[instance].instance != address(0)) revert AlreadyRegistered();
        records[instance] = Record(instance, implementation, creator, kind, version, true);
        allInstances.add(instance);
        byKind[kind].add(instance);
        byCreator[creator].add(instance);
        emit Registered(instance, kind, creator, implementation, version);
    }

    function setActive(address instance, bool active) external override onlyOwner {
        if (!allInstances.contains(instance)) revert UnknownInstance();
        records[instance].active = active;
        emit ActivationChanged(instance, active);
    }

    function getRecord(address instance) external view override returns (Record memory) {
        if (!allInstances.contains(instance)) {
            revert UnknownInstance();
        }
        return records[instance];
    }

    function isRegistered(address instance) external view override returns (bool) {
        return allInstances.contains(instance);
    }

    function allCount() external view returns (uint256) {
        return allInstances.length();
    }

    function automationInstances(bytes32 kind, uint256 offset, uint256 limit)
        external
        view
        returns (address[] memory instances)
    {
        (instances,) = _automationInstances(kind, offset, limit);
    }

    function automationInstancesWithCycle(bytes32 kind, uint256 offset, uint256 limit)
        external
        view
        returns (address[] memory instances, uint256 cycle)
    {
        return _automationInstances(kind, offset, limit);
    }

    function _automationInstances(bytes32 kind, uint256 offset, uint256 limit)
        internal
        view
        returns (address[] memory instances, uint256 cycle)
    {
        if (limit == 0) return (new address[](0), 0);
        uint256 count = byKind[kind].length();
        if (count == 0) return (new address[](0), 0);
        cycle = offset / count;
        offset = offset % count;
        uint256 end = offset > type(uint256).max - limit ? count : offset + limit;
        if (end > count) end = count;
        uint256 length = end - offset;
        instances = new address[](length);
        uint256 found;
        for (uint256 i = offset; i < end; ++i) {
            address instance = byKind[kind].at(i);
            if (!records[instance].active) continue;
            instances[found++] = instance;
        }
        assembly {
            mstore(instances, found)
        }
    }

    function byKindCount(bytes32 kind) external view returns (uint256) {
        return byKind[kind].length();
    }

    function byCreatorCount(address creator) external view returns (uint256) {
        return byCreator[creator].length();
    }

    function allAt(uint256 index) external view returns (address) {
        return allInstances.at(index);
    }

    function kindAt(bytes32 kind, uint256 index) external view returns (address) {
        return byKind[kind].at(index);
    }

    function creatorAt(address creator, uint256 index) external view returns (address) {
        return byCreator[creator].at(index);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import "../interfaces/IRegistry.sol";

contract ProtocolRegistry is Ownable2Step, IRegistry {
    using EnumerableSet for EnumerableSet.AddressSet;

    mapping(address => Record) private records;

    mapping(bytes32 => EnumerableSet.AddressSet) private byKind;

    mapping(address => EnumerableSet.AddressSet) private byCreator;

    EnumerableSet.AddressSet private allInstances;

    mapping(address => bool) public registrar;

    error UnauthorizedRegistrar();

    constructor(address initialOwner) Ownable(initialOwner) {}

    modifier onlyRegistrar() {
        if (msg.sender != owner() &&!registrar[msg.sender]) revert UnauthorizedRegistrar();
        _;
    }

    function setRegistrar(address account,bool allowed) external onlyOwner {
        if (account == address(0)) revert UnauthorizedRegistrar();
        
        registrar[account] = allowed;
    }

    function registerInstance(address instance,address creator,address implementation,bytes32 kind,uint64 version) external override onlyRegistrar {
        if (records[instance].instance !=address(0)) revert AlreadyRegistered();
        

        records[instance] = Record(instance,implementation,creator,kind,version,true);

        allInstances.add(instance);

        byKind[kind].add(instance);

        byCreator[creator].add(instance);

        emit Registered(instance,kind,creator,implementation,version);
    }

    function setActive(address instance,bool active) external override onlyOwner {
        if (!allInstances.contains(instance)) revert UnknownInstance();
        
        records[instance].active = active;

        emit ActivationChanged(instance,active);
    }

    function getRecord(address instance) external view override returns (Record memory) {
        if (!allInstances.contains(instance)) 
            revert UnknownInstance();
    
        return records[instance];
    }

    function isRegistered(address instance) external view override returns (bool) {
        return allInstances.contains(instance);
    }

    function allCount() external view returns (uint256)
    {
        return allInstances.length();
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
    function kindAt(bytes32 kind,uint256 index) external view returns (address) {
        return byKind[kind].at(index);
    }
    function creatorAt(address creator,uint256 index) external view returns (address){
        return byCreator[creator].at(index);
    }
}

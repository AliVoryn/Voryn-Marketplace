// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/manager/AccessManager.sol";
import "@openzeppelin/contracts/governance/TimelockController.sol";

 
 
contract ProtocolAccessManager is AccessManager {
    constructor(address initialAdmin)
        AccessManager(initialAdmin)
    {}
}

contract ProtocolTimelock is TimelockController {
    constructor(
        uint minDelay,
        address[] memory proposers,
        address[] memory executors,
        address admin
    )
        TimelockController(
            minDelay,
            proposers,
            executors,
            admin
        )
    {}
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import { Staking } from "../../core/Staking.sol";

library StakingDeployer {
    function deploy(address initialOwner, address rewardTreasury) external returns (address) {
        return address(new Staking(initialOwner, rewardTreasury));
    }
}

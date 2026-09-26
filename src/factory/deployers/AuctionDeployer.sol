// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import { OpenAuction } from "../../core/OpenAuction.sol";
import { DutchAuction } from "../../core/DutchAuction.sol";

library AuctionDeployer {
    function deployOpen(address initialOwner, address treasury, uint16 feeBps) external returns (address) {
        return address(new OpenAuction(initialOwner, treasury, feeBps));
    }

    function deployDutch(address initialOwner, address treasury, uint16 feeBps) external returns (address) {
        return address(new DutchAuction(initialOwner, treasury, feeBps));
    }
}

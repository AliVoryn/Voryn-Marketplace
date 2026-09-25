// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import { Raffle } from "../../core/Raffle.sol";

library RaffleDeployer {
    struct Params {
        address owner;
        address treasury;
        uint16 feeBps;
        address vrfCoordinator;
        uint256 subscriptionId;
        bytes32 keyHash;
        uint32 callbackGasLimit;
        uint16 requestConfirmations;
        bool nativePayment;
    }

    function deploy(Params memory p) external returns (address) {
        return address(
            new Raffle(
                p.owner,
                p.treasury,
                p.feeBps,
                p.vrfCoordinator,
                p.subscriptionId,
                p.keyHash,
                p.callbackGasLimit,
                p.requestConfirmations,
                p.nativePayment
            )
        );
    }
}

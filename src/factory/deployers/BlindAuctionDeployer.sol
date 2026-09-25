// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import { BlindAuction } from "../../core/BlindAuction.sol";

library BlindAuctionDeployer {
    struct Params {
        address owner;
        address payable beneficiary;
        address nft;
        uint256 tokenId;
        address treasury;
        uint16 feeBps;
        uint256 biddingTime;
        uint256 revealTime;
        uint256 reservePrice;
    }

    function deploy(Params memory p) external returns (address) {
        return address(
            new BlindAuction(
                p.owner,
                p.beneficiary,
                p.nft,
                p.tokenId,
                p.treasury,
                p.feeBps,
                p.biddingTime,
                p.revealTime,
                p.reservePrice
            )
        );
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../support/AutomationIntegrationBase.sol";

contract ProtocolAutomationGasTest is AutomationIntegrationBase {
    uint256 internal constant CONFIGURED_GAS_LIMIT = 1_000_000;

    uint256 internal constant CONFIGURED_REFUND_BATCH = 12;

    uint256 internal constant MAX_PERCENT_OF_LIMIT = 60;

    function _coolAll() internal {
        vm.cool(address(receiver));
        vm.cool(address(registry));
        vm.cool(address(openAuction));
        vm.cool(address(dutchAuction));
        vm.cool(address(blindAuction));
        vm.cool(address(marketplace));
        vm.cool(address(raffle));
        vm.cool(address(nft));
        vm.cool(address(treasury));
        vm.cool(address(paymentManager));
        vm.cool(address(coordinator));
    }

    function _measure(
        string memory label,
        ProtocolAutomationReceiver.Action action,
        address instance,
        uint256 id,
        uint256 value,
        uint256 cursor
    ) internal returns (uint256 used) {
        bytes memory meta = _metadata();
        bytes memory report = _encode(action, instance, id, value, cursor);
        _coolAll();
        vm.prank(address(forwarder));
        uint256 g = gasleft();
        receiver.onReport(meta, report);
        used = g - gasleft();
        emit log_named_uint(label, used);
        assertLe(used * 100, CONFIGURED_GAS_LIMIT * MAX_PERCENT_OF_LIMIT, label);
    }

    function test_GasOpenAuctionFinalizeWithManyBids() public {
        uint256 tokenId = _mintApproved(seller, address(openAuction));
        vm.prank(seller);
        uint256 id = openAuction.createAuction(address(nft), tokenId, 1 ether, 0.01 ether, 0, 1 days);
        for (uint256 i = 0; i < 50; ++i) {
            address b = makeAddr(string(abi.encodePacked("bidder", i)));
            vm.deal(b, 10 ether);
            vm.prank(b);
            openAuction.placeBid{ value: 1 ether + i * 0.01 ether }(id);
        }
        vm.warp(block.timestamp + 1 days + 1);
        _measure(
            "gas FINALIZE_OPEN_AUCTION (50 bids)",
            ProtocolAutomationReceiver.Action.FINALIZE_OPEN_AUCTION,
            address(openAuction),
            id,
            0,
            0
        );
    }

    function test_GasBlindAuctionFinalizeWithManyRevealedBids() public {
        uint256 n = 30;
        address[] memory bidders = new address[](n);
        bytes32[] memory secrets = new bytes32[](n);
        for (uint256 i = 0; i < n; ++i) {
            bidders[i] = makeAddr(string(abi.encodePacked("blind", i)));
            secrets[i] = keccak256(abi.encodePacked("s", i));
            bytes32 commitment = blindAuction.computeBlindedBid(2 ether + i, false, secrets[i]);
            vm.deal(bidders[i], 3 ether);
            vm.prank(bidders[i]);
            blindAuction.placeBid{ value: 3 ether }(commitment);
        }
        vm.warp(block.timestamp + BLIND_BIDDING_TIME + 1);
        for (uint256 i = 0; i < n; ++i) {
            uint256[] memory v = new uint256[](1);
            v[0] = 2 ether + i;
            bool[] memory f = new bool[](1);
            bytes32[] memory sc = new bytes32[](1);
            sc[0] = secrets[i];
            vm.prank(bidders[i]);
            blindAuction.reveal(v, f, sc);
        }
        vm.warp(blindAuction.revealEnd() + 1);
        _measure(
            "gas FINALIZE_BLIND_AUCTION (30 revealed bids)",
            ProtocolAutomationReceiver.Action.FINALIZE_BLIND_AUCTION,
            address(blindAuction),
            0,
            0,
            0
        );
        assertEq(nft.ownerOf(blindAuction.tokenId()), bidders[n - 1]);
    }

    function test_GasDutchExpire() public {
        uint256 tokenId = _mintApproved(seller, address(dutchAuction));
        vm.prank(seller);
        uint256 id = dutchAuction.createAuction(address(nft), tokenId, 2 ether, 1 ether, 0, 1 days);
        vm.warp(block.timestamp + 1 days);
        _measure(
            "gas EXPIRE_DUTCH_AUCTION",
            ProtocolAutomationReceiver.Action.EXPIRE_DUTCH_AUCTION,
            address(dutchAuction),
            id,
            0,
            0
        );
    }

    function test_GasExpireOffer() public {
        uint256 tokenId = _mint(nft, seller);
        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        uint256 id = marketplace.makeOffer{ value: 1 ether }(address(nft), tokenId, uint64(block.timestamp + 1 days));
        vm.warp(block.timestamp + 1 days);
        _measure("gas EXPIRE_OFFER", ProtocolAutomationReceiver.Action.EXPIRE_OFFER, address(marketplace), id, 0, 0);
    }

    function test_GasRequestRaffleWinnerWithManyEntrants() public {
        uint256 id = _raffleWithEntrants(100);
        vm.warp(block.timestamp + 1 days);
        _measure(
            "gas REQUEST_RAFFLE_WINNER (100 entrants, mock VRF)",
            ProtocolAutomationReceiver.Action.REQUEST_RAFFLE_WINNER,
            address(raffle),
            id,
            0,
            0
        );
    }

    function test_GasFinalizeFailedRaffle() public {
        uint256 tokenId = _mintApproved(seller, address(raffle));
        vm.prank(seller);
        uint256 id = raffle.createRaffle(address(nft), tokenId, 1 ether, 10, 10, 0, 1 days);
        vm.warp(block.timestamp + 1 days);
        _measure(
            "gas FINALIZE_FAILED_RAFFLE",
            ProtocolAutomationReceiver.Action.FINALIZE_FAILED_RAFFLE,
            address(raffle),
            id,
            0,
            0
        );
    }

    function test_GasRefundBatchFitsConfiguredGasLimit() public {
        uint256 id = _cancelledRaffleWithEntrants(100);
        _measure(
            "gas PROCESS_RAFFLE_REFUNDS (configured batch)",
            ProtocolAutomationReceiver.Action.PROCESS_RAFFLE_REFUNDS,
            address(raffle),
            id,
            CONFIGURED_REFUND_BATCH,
            0
        );
    }

    function test_GasRefundBatchOfOneHundredExceedsTheConfiguredLimit() public {
        uint256 id = _cancelledRaffleWithEntrants(100);
        bytes memory meta = _metadata();
        bytes memory report =
            _encode(ProtocolAutomationReceiver.Action.PROCESS_RAFFLE_REFUNDS, address(raffle), id, 100, 0);
        _coolAll();
        vm.prank(address(forwarder));
        uint256 g = gasleft();
        receiver.onReport(meta, report);
        uint256 used = g - gasleft();
        emit log_named_uint("gas PROCESS_RAFFLE_REFUNDS (100 entries)", used);
        assertGt(used, CONFIGURED_GAS_LIMIT, "if this fails, the batch size may be raised");
    }

    function _raffleWithEntrants(uint256 n) internal returns (uint256 id) {
        uint256 tokenId = _mintApproved(seller, address(raffle));
        vm.prank(seller);
        id = raffle.createRaffle(address(nft), tokenId, 0.01 ether, 10_000, 0, 0, 1 days);
        for (uint256 i = 0; i < n; ++i) {
            address b = makeAddr(string(abi.encodePacked("entrant", i)));
            vm.deal(b, 1 ether);
            vm.prank(b);
            raffle.buyTickets{ value: 0.01 ether }(id, 1);
        }
    }

    function _cancelledRaffleWithEntrants(uint256 n) internal returns (uint256 id) {
        id = _raffleWithEntrants(n);
        vm.warp(block.timestamp + 1 days);
        _deliver(ProtocolAutomationReceiver.Action.REQUEST_RAFFLE_WINNER, address(raffle), id, 0, 0);
        vm.warp(block.timestamp + raffle.STUCK_RAFFLE_CANCEL_DELAY());
        vm.prank(seller);
        raffle.cancelStuckRaffle(id);
    }
}

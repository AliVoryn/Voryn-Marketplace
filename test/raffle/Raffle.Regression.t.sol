// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../support/TestBase.sol";

contract RaffleRegressionTest is ProtocolTestBase {
    Raffle internal raffle;
    MockVRFCoordinatorV2Plus internal coordinator;
    uint256 internal tokenId;

    function setUp() public {
        _setUpCore();
        coordinator = _deployMockCoordinator();
        raffle = _deployRaffle(address(treasury), coordinator);
        tokenId = _mint(nft, seller);
        vm.prank(seller);
        nft.approve(address(raffle), tokenId);
    }

    function test_ForcedETHDoesNotBreakActiveEscrowAccounting() public {
        vm.prank(seller);
        uint256 id = raffle.createRaffle(address(nft), tokenId, 0.1 ether, 10, 10, 0, 1 days);
        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        raffle.buyTickets{ value: 0.1 ether }(id, 1);
        ForceSender force = new ForceSender{ value: 1 ether }();
        force.destroy(payable(address(raffle)));
        assertEq(raffle.ticketsOwnedBy(id, buyer), 1);
        assertGe(address(raffle).balance, 0.1 ether);
    }

    function test_CancelStuckRaffleReturnsNFTAfterConfiguredDelay() public {
        vm.prank(seller);
        uint256 id = raffle.createRaffle(address(nft), tokenId, 0.1 ether, 10, 10, 0, 1 days);
        vm.deal(buyer, 0.1 ether);
        vm.prank(buyer);
        raffle.buyTickets{ value: 0.1 ether }(id, 1);
        vm.warp(block.timestamp + 1 days + 1);
        vm.prank(seller);
        raffle.requestRandomWinner(id);
        vm.warp(block.timestamp + raffle.STUCK_RAFFLE_CANCEL_DELAY());
        vm.prank(seller);
        raffle.cancelStuckRaffle(id);
        assertEq(nft.ownerOf(tokenId), seller);
    }
}

contract ForceSender {
    constructor() payable { }

    function destroy(address payable target) external {
        selfdestruct(target);
    }
}

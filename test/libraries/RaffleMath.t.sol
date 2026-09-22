// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import "forge-std/Test.sol";
import "../../src/libraries/RaffleMath.sol";
import "../../src/interfaces/IRaffle.sol";

contract RaffleMathHarness {
    IRaffle.Entrant[] public entrants;

    function push(address buyer, uint128 startIndex, uint128 ticketCount) external {
        entrants.push(IRaffle.Entrant({ buyer: buyer, startIndex: startIndex, ticketCount: ticketCount }));
    }

    function find(uint256 ticketIndex) external view returns (address) {
        return RaffleMath.findEntrant(entrants, ticketIndex);
    }

    function pick(uint256 randomWord, uint256 totalTickets) external pure returns (uint256) {
        return RaffleMath.pickWinningTicket(randomWord, totalTickets);
    }
}

contract RaffleMathTest is Test {
    RaffleMathHarness internal harness;
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal carol = makeAddr("carol");

    function setUp() public {
        harness = new RaffleMathHarness();
        harness.push(alice, 0, 5);
        harness.push(bob, 5, 1);
        harness.push(carol, 6, 10);
    }

    function test_pickWinningTicket_IsModulo() public pure {
        assertEq(RaffleMath.pickWinningTicket(7, 16), 7);
        assertEq(RaffleMath.pickWinningTicket(16, 16), 0);
        assertEq(RaffleMath.pickWinningTicket(31, 16), 15);
    }

    function test_findEntrant_FirstRange() public view {
        assertEq(harness.find(0), alice);
        assertEq(harness.find(4), alice);
    }

    function test_findEntrant_SingleTicketRange() public view {
        assertEq(harness.find(5), bob);
    }

    function test_findEntrant_LastRange() public view {
        assertEq(harness.find(6), carol);
        assertEq(harness.find(15), carol);
    }

    function test_findEntrant_RevertsOnOutOfRangeIndex() public {
        vm.expectRevert(IRaffle.EntrantNotFound.selector);
        harness.find(16);
    }

    function testFuzz_findEntrant_EveryIndexResolves(uint256 ticketIndex) public view {
        ticketIndex = bound(ticketIndex, 0, 15);
        address winner = harness.find(ticketIndex);
        assertTrue(winner == alice || winner == bob || winner == carol);
    }

    function test_findEntrant_RevertsOnEmptyEntrantsList() public {
        RaffleMathHarness empty = new RaffleMathHarness();
        vm.expectRevert(IRaffle.EntrantNotFound.selector);
        empty.find(0);
    }

    function test_findEntrant_MidRangeBoundariesExactStartAndEnd() public view {
        assertEq(harness.find(5), bob);
        assertEq(harness.find(15), carol);

        assertEq(harness.find(4), alice);

        assertEq(harness.find(6), carol);
    }

    function test_pickWinningTicket_ZeroRandomWord() public pure {
        assertEq(RaffleMath.pickWinningTicket(0, 16), 0);
    }

    function test_PickWinningTicket_RevertsWhenNoTickets() public {
        vm.expectRevert(RaffleMath.NoTickets.selector);
        harness.pick(123, 0);
    }
}

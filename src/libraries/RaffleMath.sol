pragma solidity ^0.8.24;
import "../interfaces/IRaffle.sol";
library RaffleMath {
    function pickWinningTicket(uint256 randomWord, uint256 totalTickets) internal pure returns (uint256) {
        return randomWord % totalTickets;
    }
    function findEntrant(IRaffle.Entrant[] storage entrants, uint256 winningTicketIndex) internal view returns (address) {
        uint256 low = 0;
        uint256 high = entrants.length;
        while (low < high) {
            uint256 mid = (low + high) / 2;
            IRaffle.Entrant storage candidate = entrants[mid];
            uint256 rangeStart = candidate.startIndex;
            uint256 rangeEnd = rangeStart + candidate.ticketCount;
            if (winningTicketIndex < rangeStart) {
                high = mid;
            } else if (winningTicketIndex >= rangeEnd) {
                low = mid + 1;
            } else {
                return candidate.buyer;
            }
        }
        revert IRaffle.EntrantNotFound();
    }
}

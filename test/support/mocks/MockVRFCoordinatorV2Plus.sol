// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import { VRFV2PlusClient } from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";

interface IRawFulfill {
    function rawFulfillRandomWords(uint256 requestId, uint256[] calldata randomWords) external;
}

contract MockVRFCoordinatorV2Plus {
    uint256 public nextRequestId = 1;
    mapping(uint256 => address) public requester;
    mapping(uint256 => bool) public fulfilled;
    event RandomWordsRequested(
        uint256 indexed requestId, address indexed requester, VRFV2PlusClient.RandomWordsRequest req
    );

    function requestRandomWords(VRFV2PlusClient.RandomWordsRequest calldata req) external returns (uint256 requestId) {
        requestId = nextRequestId++;
        requester[requestId] = msg.sender;
        emit RandomWordsRequested(requestId, msg.sender, req);
    }

    function fulfill(uint256 requestId, uint256[] memory randomWords) external {
        require(requester[requestId] != address(0), "unknown request");
        require(!fulfilled[requestId], "already fulfilled");
        fulfilled[requestId] = true;
        IRawFulfill(requester[requestId]).rawFulfillRandomWords(requestId, randomWords);
    }

    function fulfillSingle(uint256 requestId, uint256 randomWord) external {
        require(requester[requestId] != address(0), "unknown request");
        require(!fulfilled[requestId], "already fulfilled");
        fulfilled[requestId] = true;
        uint256[] memory words = new uint256[](1);
        words[0] = randomWord;
        IRawFulfill(requester[requestId]).rawFulfillRandomWords(requestId, words);
    }
}

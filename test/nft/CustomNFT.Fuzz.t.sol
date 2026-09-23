// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../support/TestBase.sol";

contract CustomNFTFuzzTest is ProtocolTestBase {
    function setUp() public {
        _setUpCore();
    }

    function testFuzz_MintBatchCreatesExactSupply(uint8 rawLength) public {
        uint256 length = bound(uint256(rawLength), 1, 20);
        string[] memory uris = new string[](length);
        for (uint256 i; i < length; ++i) {
            uris[i] = "ipfs://token";
        }
        vm.prank(admin);
        uint256[] memory ids = nft.mintBatch(buyer, uris);
        assertEq(ids.length, length);
        assertEq(nft.totalSupply(), length);
        assertEq(nft.balanceOf(buyer), length);
    }
}

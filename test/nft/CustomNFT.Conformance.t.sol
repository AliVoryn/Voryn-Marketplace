// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../support/TestBase.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { IERC721Metadata } from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";

contract CustomNFTConformanceTest is ProtocolTestBase {
    CustomNFT internal token;

    function setUp() public {
        token = _deployNFT();
    }

    function test_ERC721AndMetadataInterfacesAreSupported() public view {
        assertTrue(token.supportsInterface(type(IERC721).interfaceId));
        assertTrue(token.supportsInterface(type(IERC721Metadata).interfaceId));
        assertTrue(token.supportsInterface(type(ICustomNFT).interfaceId));
    }

    function test_InvalidInterfaceIsNotReportedAsSupported() public view {
        assertFalse(token.supportsInterface(0xffffffff));
    }
}

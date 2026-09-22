// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

library OrderHashLib {
    bytes32 internal constant LISTING_TYPEHASH = keccak256("ListingOrder(address seller,address nft,uint256 tokenId,uint256 price,uint64 expiresAt,uint256 nonce)");
    function hashStruct(address seller, address nft, uint tokenId, uint price, uint64 expiresAt, uint nonce) internal pure returns (bytes32) {
        return keccak256(abi.encode(LISTING_TYPEHASH, seller, nft, tokenId, price, expiresAt, nonce));
    }
}

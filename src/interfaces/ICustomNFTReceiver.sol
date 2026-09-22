pragma solidity ^0.8.24;
interface ICustomNFTReceiver {
    function onCustomNFTReceived(address operator, address from, uint tokenId, bytes calldata data) external returns (bytes4);
}

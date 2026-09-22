// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IFactory {
    event InstanceCreated(address indexed instance, address indexed creator, bytes32 indexed kind, address implementation);
    event DeterministicNFTCreated(address indexed instance, address indexed creator, bytes32 indexed salt);

    function createTreasury(address feeRecipient) external returns (address instance);
    function createPaymentManager() external returns (address instance);
    function createMarketplace(address admin, address treasury, address paymentManager) external returns (address instance);
    function createCustomNFT(string calldata name_, string calldata symbol_, uint maxSupply_, address admin) external returns (address instance);
    function createCustomNFTDeterministic(string calldata name_, string calldata symbol_, uint maxSupply_, address admin, bytes32 salt) external returns (address instance);
    function createAuctionInstance(address treasury) external returns (address instance);
    function createStaking(address rewardTreasury) external returns (address instance);
    function createProtocolSuite(address admin, address feeRecipient) external returns (
        address treasury,
        address paymentManager,
        address marketplace,
        address auction,
        address staking
    );
    function creatorInstanceCount(address creator) external view returns (uint);
    function creatorInstanceAt(address creator, uint index) external view returns (address);
}

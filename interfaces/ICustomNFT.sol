// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface ICustomNFT {
    enum MintPhase { Closed, Scheduled, Active, Ended }
    enum TokenState { Nonexistent, Minted, Burned }

    event Minted(address indexed to, uint indexed tokenId, string tokenURI_);
    event Burned(address indexed owner, uint indexed tokenId);
    event Transfer(address indexed from, address indexed to, uint indexed tokenId);
    event Approval(address indexed owner, address indexed approved, uint indexed tokenId);
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);
    event BaseURIUpdated(string oldBaseURI, string newBaseURI);
    event TokenURIUpdated(uint indexed tokenId, string oldTokenURI, string newTokenURI);
    event MintWindowUpdated(uint64 startAt, uint64 endAt);
    event WalletMintLimitUpdated(uint oldLimit, uint newLimit);

    error ZeroAddress();
    error TokenDoesNotExist(uint tokenId);
    error TokenAlreadyExists(uint tokenId);
    error NotAuthorized(address caller, uint tokenId);
    error InvalidReceiver();
    error MaxSupplyExceeded();
    error WalletMintLimitExceeded();
    error TokenURIUnset(uint tokenId);
    error InvalidTokenURI();
    error InvalidMintWindow();
    error MintNotActive();
    error BatchTooLarge();

    function mint(address to, string calldata tokenURI_) external returns (uint tokenId);
    function mintBatch(address to, string[] calldata tokenURIs_) external returns (uint[] memory tokenIds);
    function burn(uint tokenId) external;
    function transferFrom(address from, address to, uint tokenId) external;
    function safeTransferFrom(address from, address to, uint tokenId) external;
    function approve(address approved, uint tokenId) external;
    function revokeApproval(uint tokenId) external;
    function setApprovalForAll(address operator, bool approved) external;
    function ownerOf(uint tokenId) external view returns (address);
    function balanceOf(address owner) external view returns (uint);
    function getApproved(uint tokenId) external view returns (address);
    function isApprovedForAll(address owner, address operator) external view returns (bool);
    function exists(uint tokenId) external view returns (bool);
    function tokenURI(uint tokenId) external view returns (string memory);
    function totalSupply() external view returns (uint);
    function maxSupply() external view returns (uint);
    function tokensOfOwner(address owner) external view returns (uint[] memory);
    function walletMinted(address owner) external view returns (uint);
    function tokenState(uint tokenId) external view returns (TokenState);
    function currentMintPhase() external view returns (MintPhase);
    function mintWindow() external view returns (uint64 startAt, uint64 endAt);
    function setWalletMintLimit(uint limit) external;
    function setMintWindow(uint64 startAt, uint64 endAt) external;
    function setTokenURI(uint tokenId, string calldata tokenURI_) external;
}

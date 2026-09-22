// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface ICustomNFT {
    enum MintPhase {
        Closed,
        Scheduled,
        Active,
        Ended
    }
    enum TokenState {
        Nonexistent,
        Minted,
        Burned
    }
    event Minted(address indexed to, uint256 indexed tokenId, string tokenURI_);
    event Burned(address indexed owner, uint256 indexed tokenId);
    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);
    event BaseURIUpdated(string oldBaseURI, string newBaseURI);
    event TokenURIUpdated(uint256 indexed tokenId, string oldTokenURI, string newTokenURI);
    event MintWindowUpdated(uint64 startAt, uint64 endAt);
    event WalletMintLimitUpdated(uint256 oldLimit, uint256 newLimit);
    error ZeroAddress();
    error InvalidOperator();
    error TokenDoesNotExist(uint256 tokenId);
    error TokenAlreadyExists(uint256 tokenId);
    error NotAuthorized(address caller, uint256 tokenId);
    error InvalidReceiver();
    error MaxSupplyExceeded();
    error WalletMintLimitExceeded();
    error InvalidTokenURI();
    error InvalidMintWindow();
    error MintNotActive();
    error InvalidBatchSize();
    function mint(address to, string calldata tokenURI_) external returns (uint256 tokenId);
    function mintBatch(address to, string[] calldata tokenURIs_) external returns (uint256[] memory tokenIds);
    function burn(uint256 tokenId) external;
    function transferFrom(address from, address to, uint256 tokenId) external;
    function safeTransferFrom(address from, address to, uint256 tokenId) external;
    function safeTransferFrom(address from, address to, uint256 tokenId, bytes calldata data) external;
    function approve(address approved, uint256 tokenId) external;
    function revokeApproval(uint256 tokenId) external;
    function setApprovalForAll(address operator, bool approved) external;
    function ownerOf(uint256 tokenId) external view returns (address);
    function balanceOf(address owner) external view returns (uint256);
    function getApproved(uint256 tokenId) external view returns (address);
    function isApprovedForAll(address owner, address operator) external view returns (bool);
    function exists(uint256 tokenId) external view returns (bool);
    function tokenURI(uint256 tokenId) external view returns (string memory);
    function totalSupply() external view returns (uint256);
    function maxSupply() external view returns (uint256);
    function tokensOfOwner(address owner) external view returns (uint256[] memory);
    function walletMinted(address owner) external view returns (uint256);
    function tokenState(uint256 tokenId) external view returns (TokenState);
    function currentMintPhase() external view returns (MintPhase);
    function mintWindow() external view returns (uint64 startAt, uint64 endAt);
    function setWalletMintLimit(uint256 limit) external;
    function setMintWindow(uint64 startAt, uint64 endAt) external;
    function setTokenURI(uint256 tokenId, string calldata tokenURI_) external;
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { IERC721Metadata } from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";
import { IERC721Receiver } from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import { ICustomNFT } from "../interfaces/ICustomNFT.sol";

contract CustomNFT is AccessControl, Pausable, ReentrancyGuard, ICustomNFT {
    using Strings for uint256;
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 public constant METADATA_ROLE = keccak256("METADATA_ROLE");
    uint256 public constant MAX_BATCH_MINT = 100;
    string public name;
    string public symbol;
    string private baseURIValue;
    uint256 private nextTokenId = 1;
    uint256 private supply;
    uint256 public immutable override maxSupply;
    uint256 public walletMintLimit;
    uint64 private mintStartAt;
    uint64 private mintEndAt;
    mapping(uint256 => address) private owners;
    mapping(address => uint256) private balances;
    mapping(uint256 => address) private tokenApprovals;
    mapping(address => mapping(address => bool)) private operatorApprovals;
    mapping(uint256 => string) private tokenURIs;
    mapping(address => uint256) private mintedByWallet;
    mapping(address => uint256[]) private ownedTokens;
    mapping(uint256 => uint256) private ownedTokenIndex;

    constructor(string memory name_, string memory symbol_, uint256 maxSupply_, address admin) {
        if (admin == address(0)) revert ZeroAddress();
        name = name_;
        symbol = symbol_;
        maxSupply = maxSupply_;
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(MINTER_ROLE, admin);
        _grantRole(OPERATOR_ROLE, admin);
        _grantRole(METADATA_ROLE, admin);
    }

    function mint(address to, string calldata tokenURI_)
        external
        override
        onlyRole(MINTER_ROLE)
        whenNotPaused
        returns (uint256 tokenId)
    {
        _requireMintActive();
        tokenId = _mintOne(to, tokenURI_);
    }

    function mintBatch(address to, string[] calldata tokenURIs_)
        external
        override
        onlyRole(MINTER_ROLE)
        whenNotPaused
        returns (uint256[] memory tokenIds)
    {
        _requireMintActive();
        uint256 length = tokenURIs_.length;
        if (length == 0 || length > MAX_BATCH_MINT) revert InvalidBatchSize();
        if (to == address(0)) revert ZeroAddress();
        tokenIds = new uint256[](length);
        for (uint256 i; i < length; ++i) {
            tokenIds[i] = _mintOne(to, tokenURIs_[i]);
        }
    }

    function setMintWindow(uint64 startAt, uint64 endAt) external override onlyRole(DEFAULT_ADMIN_ROLE) {
        if (endAt != 0 && endAt <= startAt) revert InvalidMintWindow();
        mintStartAt = startAt;
        mintEndAt = endAt;
        emit MintWindowUpdated(startAt, endAt);
    }

    function currentMintPhase() public view override returns (MintPhase) {
        if (mintStartAt == 0 && mintEndAt == 0) return MintPhase.Active;
        if (mintStartAt != 0 && block.timestamp < mintStartAt) return MintPhase.Scheduled;
        if (mintEndAt != 0 && block.timestamp >= mintEndAt) return MintPhase.Ended;
        return MintPhase.Active;
    }

    function mintWindow() external view override returns (uint64 startAt, uint64 endAt) {
        return (mintStartAt, mintEndAt);
    }

    function burn(uint256 tokenId) external override whenNotPaused {
        address owner = ownerOf(tokenId);
        if (!_isAuthorized(owner, msg.sender, tokenId)) revert NotAuthorized(msg.sender, tokenId);
        _removeTokenFromOwnerEnumeration(owner, tokenId);
        delete tokenApprovals[tokenId];
        delete owners[tokenId];
        delete tokenURIs[tokenId];
        balances[owner] -= 1;
        supply -= 1;
        emit Burned(owner, tokenId);
        emit Transfer(owner, address(0), tokenId);
    }

    function transferFrom(address from, address to, uint256 tokenId) external override whenNotPaused {
        _transfer(from, to, tokenId, msg.sender);
    }

    function safeTransferFrom(address from, address to, uint256 tokenId) external override nonReentrant whenNotPaused {
        _safeTransfer(from, to, tokenId, msg.sender, bytes(""));
    }

    function safeTransferFrom(address from, address to, uint256 tokenId, bytes calldata data)
        external
        override
        nonReentrant
        whenNotPaused
    {
        _safeTransfer(from, to, tokenId, msg.sender, data);
    }

    function approve(address approved, uint256 tokenId) external override whenNotPaused {
        address owner = ownerOf(tokenId);
        if (msg.sender != owner && !operatorApprovals[owner][msg.sender]) revert NotAuthorized(msg.sender, tokenId);
        tokenApprovals[tokenId] = approved;
        emit Approval(owner, approved, tokenId);
    }

    function revokeApproval(uint256 tokenId) external override whenNotPaused {
        address owner = ownerOf(tokenId);
        if (msg.sender != owner && !operatorApprovals[owner][msg.sender]) revert NotAuthorized(msg.sender, tokenId);
        delete tokenApprovals[tokenId];
        emit Approval(owner, address(0), tokenId);
    }

    function setApprovalForAll(address operator, bool approved) external override whenNotPaused {
        if (operator == address(0)) revert ZeroAddress();
        if (operator == msg.sender) revert InvalidOperator();
        operatorApprovals[msg.sender][operator] = approved;
        emit ApprovalForAll(msg.sender, operator, approved);
    }

    function supportsInterface(bytes4 interfaceId) public view override(AccessControl) returns (bool) {
        return interfaceId == type(IERC721).interfaceId || interfaceId == type(IERC721Metadata).interfaceId
            || interfaceId == type(ICustomNFT).interfaceId || super.supportsInterface(interfaceId);
    }

    function ownerOf(uint256 tokenId) public view override returns (address) {
        address owner = owners[tokenId];
        if (owner == address(0)) revert TokenDoesNotExist(tokenId);
        return owner;
    }

    function balanceOf(address owner) external view override returns (uint256) {
        if (owner == address(0)) revert ZeroAddress();
        return balances[owner];
    }

    function getApproved(uint256 tokenId) external view override returns (address) {
        ownerOf(tokenId);
        return tokenApprovals[tokenId];
    }

    function isApprovedForAll(address owner, address operator) external view override returns (bool) {
        return operatorApprovals[owner][operator];
    }

    function exists(uint256 tokenId) external view override returns (bool) {
        return owners[tokenId] != address(0);
    }

    function tokenURI(uint256 tokenId) external view override returns (string memory) {
        ownerOf(tokenId);
        string memory local = tokenURIs[tokenId];
        if (bytes(local).length != 0) return local;
        if (bytes(baseURIValue).length == 0) return "";
        return string.concat(baseURIValue, tokenId.toString());
    }

    function totalSupply() external view override returns (uint256) {
        return supply;
    }

    function tokensOfOwner(address owner) external view override returns (uint256[] memory) {
        return ownedTokens[owner];
    }

    function walletMinted(address owner) external view override returns (uint256) {
        return mintedByWallet[owner];
    }

    function tokenState(uint256 tokenId) external view override returns (TokenState) {
        if (owners[tokenId] != address(0)) return TokenState.Minted;
        if (tokenId != 0 && tokenId < nextTokenId) return TokenState.Burned;
        return TokenState.Nonexistent;
    }

    function setWalletMintLimit(uint256 limit) external override onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256 oldLimit = walletMintLimit;
        walletMintLimit = limit;
        emit WalletMintLimitUpdated(oldLimit, limit);
    }

    function setTokenURI(uint256 tokenId, string calldata tokenURI_) external override onlyRole(METADATA_ROLE) {
        ownerOf(tokenId);
        if (bytes(tokenURI_).length == 0) revert InvalidTokenURI();
        string memory oldURI = tokenURIs[tokenId];
        tokenURIs[tokenId] = tokenURI_;
        emit TokenURIUpdated(tokenId, oldURI, tokenURI_);
    }

    function setBaseURI(string calldata newBaseURI) external onlyRole(METADATA_ROLE) {
        string memory oldURI = baseURIValue;
        baseURIValue = newBaseURI;
        emit BaseURIUpdated(oldURI, newBaseURI);
    }

    function pause() external onlyRole(OPERATOR_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(OPERATOR_ROLE) {
        _unpause();
    }

    function grantMinter(address account) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _grantRole(MINTER_ROLE, account);
    }

    function revokeMinter(address account) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _revokeRole(MINTER_ROLE, account);
    }

    function _requireMintActive() internal view {
        if (currentMintPhase() != MintPhase.Active) revert MintNotActive();
    }

    function _mintOne(address to, string memory tokenURI_) internal returns (uint256 tokenId) {
        if (to == address(0)) revert ZeroAddress();
        if (maxSupply != 0 && supply >= maxSupply) revert MaxSupplyExceeded();
        if (walletMintLimit != 0 && mintedByWallet[to] >= walletMintLimit) revert WalletMintLimitExceeded();
        tokenId = nextTokenId++;
        if (owners[tokenId] != address(0)) revert TokenAlreadyExists(tokenId);
        owners[tokenId] = to;
        balances[to] += 1;
        mintedByWallet[to] += 1;
        supply += 1;
        tokenURIs[tokenId] = tokenURI_;
        _addTokenToOwnerEnumeration(to, tokenId);
        emit Minted(to, tokenId, tokenURI_);
        emit Transfer(address(0), to, tokenId);
    }

    function _safeTransfer(address from, address to, uint256 tokenId, address caller, bytes memory data) internal {
        _transfer(from, to, tokenId, caller);
        if (to.code.length == 0) return;
        bytes4 response = IERC721Receiver(to).onERC721Received(caller, from, tokenId, data);
        if (response != IERC721Receiver.onERC721Received.selector) revert InvalidReceiver();
    }

    function _transfer(address from, address to, uint256 tokenId, address caller) internal {
        if (to == address(0)) revert ZeroAddress();
        address owner = ownerOf(tokenId);
        if (owner != from) revert NotAuthorized(caller, tokenId);
        if (!_isAuthorized(owner, caller, tokenId)) revert NotAuthorized(caller, tokenId);
        delete tokenApprovals[tokenId];
        _removeTokenFromOwnerEnumeration(from, tokenId);
        _addTokenToOwnerEnumeration(to, tokenId);
        owners[tokenId] = to;
        balances[from] -= 1;
        balances[to] += 1;
        emit Transfer(from, to, tokenId);
    }

    function _isAuthorized(address owner, address caller, uint256 tokenId) internal view returns (bool) {
        return caller == owner || tokenApprovals[tokenId] == caller || operatorApprovals[owner][caller];
    }

    function _addTokenToOwnerEnumeration(address to, uint256 tokenId) internal {
        ownedTokenIndex[tokenId] = ownedTokens[to].length;
        ownedTokens[to].push(tokenId);
    }

    function _removeTokenFromOwnerEnumeration(address from, uint256 tokenId) internal {
        uint256 lastIndex = ownedTokens[from].length - 1;
        uint256 tokenIndex = ownedTokenIndex[tokenId];
        if (tokenIndex != lastIndex) {
            uint256 lastTokenId = ownedTokens[from][lastIndex];
            ownedTokens[from][tokenIndex] = lastTokenId;
            ownedTokenIndex[lastTokenId] = tokenIndex;
        }
        ownedTokens[from].pop();
        delete ownedTokenIndex[tokenId];
    }
}

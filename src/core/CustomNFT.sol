pragma solidity ^0.8.24;
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "../interfaces/ICustomNFT.sol";
import "../interfaces/ICustomNFTReceiver.sol";
contract CustomNFT is AccessControl, Pausable, ReentrancyGuard, ICustomNFT {
    using Strings for uint;
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 public constant METADATA_ROLE = keccak256("METADATA_ROLE");
    uint public constant MAX_BATCH_MINT = 100;
    string public name;
    string public symbol;
    string private baseURIValue;
    uint private nextTokenId = 1;
    uint private supply;
    uint public immutable override maxSupply;
    uint public walletMintLimit;
    uint64 private mintStartAt;
    uint64 private mintEndAt;
    mapping(uint => address) private owners;
    mapping(address => uint) private balances;
    mapping(uint => address) private tokenApprovals;
    mapping(address => mapping(address => bool)) private operatorApprovals;
    mapping(uint => string) private tokenURIs;
    mapping(address => uint) private mintedByWallet;
    mapping(address => uint[]) private ownedTokens;
    mapping(uint => uint) private ownedTokenIndex;
    constructor(string memory name_, string memory symbol_, uint maxSupply_, address admin) {
        if (admin == address(0)) revert ZeroAddress();
        name = name_;
        symbol = symbol_;
        maxSupply = maxSupply_;
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(MINTER_ROLE, admin);
        _grantRole(OPERATOR_ROLE, admin);
        _grantRole(METADATA_ROLE, admin);
    }
    function mint(address to, string calldata tokenURI_) external override onlyRole(MINTER_ROLE) whenNotPaused returns (uint tokenId) {
        _requireMintActive();
        tokenId = _mintOne(to, tokenURI_);
    }
    function mintBatch(address to, string[] calldata tokenURIs_) external override onlyRole(MINTER_ROLE) whenNotPaused returns (uint[] memory tokenIds) {
        _requireMintActive();
        uint length = tokenURIs_.length;
        if (length == 0 || length > MAX_BATCH_MINT) revert BatchTooLarge();
        if (to == address(0)) revert ZeroAddress();
        tokenIds = new uint[](length);
        for (uint i; i < length; ++i) tokenIds[i] = _mintOne(to, tokenURIs_[i]);
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
    function burn(uint tokenId) external override whenNotPaused {
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
    function transferFrom(address from, address to, uint tokenId) external override whenNotPaused {
        _transfer(from, to, tokenId, msg.sender);
    }
    function safeTransferFrom(address from, address to, uint tokenId) external override nonReentrant whenNotPaused {
        _transfer(from, to, tokenId, msg.sender);
        if (to.code.length == 0) return;
        bytes memory payload = abi.encodeCall(
            ICustomNFTReceiver.onCustomNFTReceived,
            (msg.sender, from, tokenId, bytes(""))
        );
        (bool success, bytes memory returndata) = to.call(payload);
        if (!success || returndata.length != 32) revert InvalidReceiver();
        if (abi.decode(returndata, (bytes4)) != ICustomNFTReceiver.onCustomNFTReceived.selector) revert InvalidReceiver();
    }
    function approve(address approved, uint tokenId) external override whenNotPaused {
        address owner = ownerOf(tokenId);
        if (msg.sender != owner && !operatorApprovals[owner][msg.sender]) revert NotAuthorized(msg.sender, tokenId);
        tokenApprovals[tokenId] = approved;
        emit Approval(owner, approved, tokenId);
    }
    function revokeApproval(uint tokenId) external override whenNotPaused {
        address owner = ownerOf(tokenId);
        if (msg.sender != owner && !operatorApprovals[owner][msg.sender]) revert NotAuthorized(msg.sender, tokenId);
        delete tokenApprovals[tokenId];
        emit Approval(owner, address(0), tokenId);
    }
    function setApprovalForAll(address operator, bool approved) external override whenNotPaused {
        if (operator == address(0)) revert ZeroAddress();
        operatorApprovals[msg.sender][operator] = approved;
        emit ApprovalForAll(msg.sender, operator, approved);
    }
    function ownerOf(uint tokenId) public view override returns (address) {
        address owner = owners[tokenId];
        if (owner == address(0)) revert TokenDoesNotExist(tokenId);
        return owner;
    }
    function balanceOf(address owner) external view override returns (uint) {
        if (owner == address(0)) revert ZeroAddress();
        return balances[owner];
    }
    function getApproved(uint tokenId) external view override returns (address) {
        ownerOf(tokenId);
        return tokenApprovals[tokenId];
    }
    function isApprovedForAll(address owner, address operator) external view override returns (bool) {
        return operatorApprovals[owner][operator];
    }
    function exists(uint tokenId) external view override returns (bool) {
        return owners[tokenId] != address(0);
    }
    function tokenURI(uint tokenId) external view override returns (string memory) {
        ownerOf(tokenId);
        string memory local = tokenURIs[tokenId];
        if (bytes(local).length != 0) return local;
        if (bytes(baseURIValue).length == 0) return "";
        return string.concat(baseURIValue, tokenId.toString());
    }
    function totalSupply() external view override returns (uint) { return supply; }
    function tokensOfOwner(address owner) external view override returns (uint[] memory) { return ownedTokens[owner]; }
    function walletMinted(address owner) external view override returns (uint) { return mintedByWallet[owner]; }
    function tokenState(uint tokenId) external view override returns (TokenState) {
        if (owners[tokenId] != address(0)) return TokenState.Minted;
        if (tokenId != 0 && tokenId < nextTokenId) return TokenState.Burned;
        return TokenState.Nonexistent;
    }
    function setWalletMintLimit(uint limit) external override onlyRole(DEFAULT_ADMIN_ROLE) {
        uint oldLimit = walletMintLimit;
        walletMintLimit = limit;
        emit WalletMintLimitUpdated(oldLimit, limit);
    }
    function setTokenURI(uint tokenId, string calldata tokenURI_) external override onlyRole(METADATA_ROLE) {
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
    function pause() external onlyRole(OPERATOR_ROLE) { _pause(); }
    function unpause() external onlyRole(OPERATOR_ROLE) { _unpause(); }
    function grantMinter(address account) external onlyRole(DEFAULT_ADMIN_ROLE) { _grantRole(MINTER_ROLE, account); }
    function revokeMinter(address account) external onlyRole(DEFAULT_ADMIN_ROLE) { _revokeRole(MINTER_ROLE, account); }
    function _requireMintActive() internal view {
        if (currentMintPhase() != MintPhase.Active) revert MintNotActive();
    }
    function _mintOne(address to, string memory tokenURI_) internal returns (uint tokenId) {
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
    function _transfer(address from, address to, uint tokenId, address caller) internal {
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
    function _isAuthorized(address owner, address caller, uint tokenId) internal view returns (bool) {
        return caller == owner || tokenApprovals[tokenId] == caller || operatorApprovals[owner][caller] || hasRole(OPERATOR_ROLE, caller);
    }
    function _addTokenToOwnerEnumeration(address to, uint tokenId) internal {
        ownedTokenIndex[tokenId] = ownedTokens[to].length;
        ownedTokens[to].push(tokenId);
    }
    function _removeTokenFromOwnerEnumeration(address from, uint tokenId) internal {
        uint lastIndex = ownedTokens[from].length - 1;
        uint tokenIndex = ownedTokenIndex[tokenId];
        if (tokenIndex != lastIndex) {
            uint lastTokenId = ownedTokens[from][lastIndex];
            ownedTokens[from][tokenIndex] = lastTokenId;
            ownedTokenIndex[lastTokenId] = tokenIndex;
        }
        ownedTokens[from].pop();
        delete ownedTokenIndex[tokenId];
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../support/TestBase.sol";

contract CustomNFTSecurityTest is ProtocolTestBase {
    function setUp() public {
        _setUpCore();
    }

    function test_NonMinterCannotMint() public {
        vm.prank(attacker);
        vm.expectRevert();
        nft.mint(attacker, "uri");
    }

    function test_NonOperatorCannotPause() public {
        vm.prank(attacker);
        vm.expectRevert();
        nft.pause();
    }

    function test_UnauthorizedAccountsCannotAdministerTheCollection() public {
        uint256 tokenId = _mint(nft, seller);
        vm.startPrank(attacker);
        vm.expectRevert();
        nft.setBaseURI("ipfs://evil/");
        vm.expectRevert();
        nft.setTokenURI(tokenId, "ipfs://evil");
        vm.expectRevert();
        nft.setMintWindow(1, 2);
        vm.expectRevert();
        nft.setWalletMintLimit(1);
        vm.expectRevert();
        nft.grantMinter(attacker);
        vm.expectRevert();
        nft.unpause();
        vm.stopPrank();
    }

    function test_UnapprovedAccountsCannotMoveOrApproveTokens() public {
        uint256 tokenId = _mint(nft, seller);
        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSelector(ICustomNFT.NotAuthorized.selector, attacker, tokenId));
        nft.transferFrom(seller, attacker, tokenId);
        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSelector(ICustomNFT.NotAuthorized.selector, attacker, tokenId));
        nft.safeTransferFrom(seller, attacker, tokenId);
        vm.expectRevert(abi.encodeWithSelector(ICustomNFT.TokenDoesNotExist.selector, 999));
        nft.getApproved(999);
        assertEq(nft.ownerOf(tokenId), seller);
    }

    function test_SafeTransferReceiverCannotReenterTheCollection() public {
        uint256 tokenId = _mint(nft, seller);
        ReentrantNFTReceiver receiver = new ReentrantNFTReceiver(nft, buyer);
        vm.prank(seller);
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        nft.safeTransferFrom(seller, address(receiver), tokenId);
        assertEq(nft.ownerOf(tokenId), seller);
    }
}

contract ReentrantNFTReceiver is IERC721Receiver {
    CustomNFT internal immutable token;
    address internal immutable sink;

    constructor(CustomNFT token_, address sink_) {
        token = token_;
        sink = sink_;
    }

    function onERC721Received(address, address, uint256 tokenId, bytes calldata) external returns (bytes4) {
        token.safeTransferFrom(address(this), sink, tokenId);
        return IERC721Receiver.onERC721Received.selector;
    }
}

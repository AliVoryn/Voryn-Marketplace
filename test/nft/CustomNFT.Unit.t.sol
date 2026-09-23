// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../support/TestBase.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

contract AcceptNFTReceiver is IERC721Receiver {
    bool public called;
    address public operator;
    address public from;
    uint256 public tokenId;

    function onERC721Received(address operator_, address from_, uint256 tokenId_, bytes calldata)
        external
        override
        returns (bytes4)
    {
        called = true;
        operator = operator_;
        from = from_;
        tokenId = tokenId_;
        return IERC721Receiver.onERC721Received.selector;
    }
}

contract RejectNFTReceiver is IERC721Receiver {
    function onERC721Received(address, address, uint256, bytes calldata) external pure override returns (bytes4) {
        return bytes4(0);
    }
}

contract CustomNFTUnitTest is ProtocolTestBase {
    function setUp() public {
        _setUpCore();
    }

    function test_Mint_AssignsStateAndEnumeration() public {
        uint256 tokenId = _mint(nft, seller);

        assertEq(tokenId, 1);
        assertEq(nft.ownerOf(tokenId), seller);
        assertEq(nft.balanceOf(seller), 1);
        assertEq(nft.totalSupply(), 1);
        assertEq(nft.walletMinted(seller), 1);
        assertEq(uint8(nft.tokenState(tokenId)), uint8(ICustomNFT.TokenState.Minted));
        assertEq(nft.tokensOfOwner(seller)[0], tokenId);
        assertEq(nft.tokenURI(tokenId), "ipfs://token");
    }

    function test_Mint_RevertsForUnauthorizedAndZeroAddress() public {
        vm.prank(attacker);
        vm.expectRevert();
        nft.mint(seller, "uri");

        vm.prank(admin);
        vm.expectRevert(ICustomNFT.ZeroAddress.selector);
        nft.mint(address(0), "uri");
    }

    function test_MintBatch_EnforcesZeroAndMaximumBoundaries() public {
        string[] memory empty = new string[](0);
        vm.prank(admin);
        vm.expectRevert(ICustomNFT.InvalidBatchSize.selector);
        nft.mintBatch(seller, empty);

        string[] memory uris = new string[](100);
        for (uint256 i; i < uris.length; ++i) {
            uris[i] = "uri";
        }
        vm.prank(admin);
        uint256[] memory tokenIds = nft.mintBatch(seller, uris);
        assertEq(tokenIds.length, 100);
        assertEq(nft.totalSupply(), 100);
    }

    function test_Mint_EnforcesMaxSupplyBoundary() public {
        CustomNFT limited = new CustomNFT("Limited", "LMT", 1, admin);
        _mintOne(limited, seller);

        vm.prank(admin);
        vm.expectRevert(ICustomNFT.MaxSupplyExceeded.selector);
        limited.mint(seller, "uri");
    }

    function test_Mint_EnforcesWalletLimitBoundary() public {
        vm.prank(admin);
        nft.setWalletMintLimit(2);
        _mint(nft, seller);
        _mint(nft, seller);

        vm.prank(admin);
        vm.expectRevert(ICustomNFT.WalletMintLimitExceeded.selector);
        nft.mint(seller, "uri");
    }

    function test_MintWindow_EnforcesScheduledActiveAndEndedBoundaries() public {
        uint64 startAt = uint64(block.timestamp + 1 days);
        uint64 endAt = startAt + 1 days;
        vm.prank(admin);
        nft.setMintWindow(startAt, endAt);
        assertEq(uint8(nft.currentMintPhase()), uint8(ICustomNFT.MintPhase.Scheduled));

        vm.prank(admin);
        vm.expectRevert(ICustomNFT.MintNotActive.selector);
        nft.mint(seller, "uri");

        vm.warp(startAt);
        assertEq(uint8(nft.currentMintPhase()), uint8(ICustomNFT.MintPhase.Active));
        _mint(nft, seller);

        vm.warp(endAt);
        assertEq(uint8(nft.currentMintPhase()), uint8(ICustomNFT.MintPhase.Ended));
        vm.prank(admin);
        vm.expectRevert(ICustomNFT.MintNotActive.selector);
        nft.mint(seller, "uri");
    }

    function test_SetMintWindow_RejectsInvalidRange() public {
        vm.prank(admin);
        vm.expectRevert(ICustomNFT.InvalidMintWindow.selector);
        nft.setMintWindow(2, 1);
    }

    function test_TransferApprovalOperatorAndEnumeration() public {
        uint256 tokenId = _mint(nft, seller);
        vm.prank(seller);
        nft.approve(buyer, tokenId);
        vm.prank(buyer);
        nft.transferFrom(seller, buyer, tokenId);

        assertEq(nft.ownerOf(tokenId), buyer);
        assertEq(nft.getApproved(tokenId), address(0));
        assertEq(nft.tokensOfOwner(seller).length, 0);
        assertEq(nft.tokensOfOwner(buyer)[0], tokenId);

        uint256 secondTokenId = _mint(nft, seller);
        vm.prank(seller);
        nft.setApprovalForAll(buyer, true);
        vm.prank(buyer);
        nft.transferFrom(seller, buyer2, secondTokenId);
        assertEq(nft.ownerOf(secondTokenId), buyer2);
    }

    function test_RevokeApproval_PreventsApprovedTransfer() public {
        uint256 tokenId = _mint(nft, seller);
        vm.prank(seller);
        nft.approve(buyer, tokenId);
        vm.prank(seller);
        nft.revokeApproval(tokenId);

        vm.prank(buyer);
        vm.expectRevert();
        nft.transferFrom(seller, buyer, tokenId);
    }

    function test_Burn_UpdatesStateAndEnumeration() public {
        uint256 tokenId = _mint(nft, seller);
        vm.prank(seller);
        nft.burn(tokenId);

        assertEq(nft.totalSupply(), 0);
        assertEq(nft.balanceOf(seller), 0);
        assertEq(nft.tokensOfOwner(seller).length, 0);
        assertEq(uint8(nft.tokenState(tokenId)), uint8(ICustomNFT.TokenState.Burned));
        vm.expectRevert(abi.encodeWithSelector(ICustomNFT.TokenDoesNotExist.selector, tokenId));
        nft.ownerOf(tokenId);
    }

    function test_SafeTransfer_AcceptsReceiverAndRejectsInvalidReceiver() public {
        uint256 tokenId = _mint(nft, seller);
        AcceptNFTReceiver receiver = new AcceptNFTReceiver();
        vm.prank(seller);
        nft.safeTransferFrom(seller, address(receiver), tokenId);
        assertTrue(receiver.called());
        assertEq(receiver.from(), seller);
        assertEq(receiver.tokenId(), tokenId);

        uint256 secondTokenId = _mint(nft, seller);
        RejectNFTReceiver rejectReceiver = new RejectNFTReceiver();
        vm.prank(seller);
        vm.expectRevert(ICustomNFT.InvalidReceiver.selector);
        nft.safeTransferFrom(seller, address(rejectReceiver), secondTokenId);
        assertEq(nft.ownerOf(secondTokenId), seller);
    }

    function _mintOne(CustomNFT token, address to) internal returns (uint256 tokenId) {
        vm.prank(admin);
        tokenId = token.mint(to, "uri");
    }

    function test_Constructor_RevertsForZeroAdmin() public {
        vm.expectRevert(ICustomNFT.ZeroAddress.selector);
        new CustomNFT("X", "X", 100, address(0));
    }

    function test_BalanceOf_RevertsForZeroAddress() public {
        vm.expectRevert(ICustomNFT.ZeroAddress.selector);
        nft.balanceOf(address(0));
    }

    function test_MintBatch_RevertsAboveMaxBatchBoundary() public {
        string[] memory uris = new string[](101);
        for (uint256 i; i < uris.length; ++i) {
            uris[i] = "uri";
        }
        vm.prank(admin);
        vm.expectRevert(ICustomNFT.InvalidBatchSize.selector);
        nft.mintBatch(seller, uris);
    }

    function test_MintBatch_RevertsForZeroAddress() public {
        string[] memory uris = new string[](1);
        uris[0] = "uri";
        vm.prank(admin);
        vm.expectRevert(ICustomNFT.ZeroAddress.selector);
        nft.mintBatch(address(0), uris);
    }

    function test_TokenState_NonexistentForNeverMintedId() public {
        assertEq(uint8(nft.tokenState(999)), uint8(ICustomNFT.TokenState.Nonexistent));
    }

    function test_TokenURI_FallsBackToBaseURIThenEmpty() public {
        uint256 tokenId = _mint(nft, seller);

        vm.prank(admin);
        uint256 blankToken = nft.mint(seller, "");
        assertEq(nft.tokenURI(blankToken), "");
        vm.prank(admin);
        nft.setBaseURI("ipfs://base/");
        assertEq(nft.tokenURI(blankToken), string.concat("ipfs://base/", vm.toString(blankToken)));
        vm.prank(admin);
        nft.setTokenURI(tokenId, "ipfs://override");
        assertEq(nft.tokenURI(tokenId), "ipfs://override");
    }

    function test_SetTokenURI_RevertsForEmptyString() public {
        uint256 tokenId = _mint(nft, seller);
        vm.prank(admin);
        vm.expectRevert(ICustomNFT.InvalidTokenURI.selector);
        nft.setTokenURI(tokenId, "");
    }

    function test_Approve_RevertsForUnauthorizedCaller() public {
        uint256 tokenId = _mint(nft, seller);
        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSelector(ICustomNFT.NotAuthorized.selector, attacker, tokenId));
        nft.approve(buyer, tokenId);
    }

    function test_SetApprovalForAll_RevertsForZeroOperator() public {
        vm.prank(seller);
        vm.expectRevert(ICustomNFT.ZeroAddress.selector);
        nft.setApprovalForAll(address(0), true);
    }

    function test_TransferFrom_RevertsForZeroRecipient() public {
        uint256 tokenId = _mint(nft, seller);
        vm.prank(seller);
        vm.expectRevert(ICustomNFT.ZeroAddress.selector);
        nft.transferFrom(seller, address(0), tokenId);
    }

    function test_TransferFrom_RevertsWhenFromIsNotOwner() public {
        uint256 tokenId = _mint(nft, seller);
        vm.prank(seller);
        vm.expectRevert(abi.encodeWithSelector(ICustomNFT.NotAuthorized.selector, seller, tokenId));
        nft.transferFrom(buyer, seller, tokenId);
    }

    function test_Burn_OperatorRoleCannotBurnWithoutTransferAuthority() public {
        uint256 tokenId = _mint(nft, seller);
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(ICustomNFT.NotAuthorized.selector, admin, tokenId));
        nft.burn(tokenId);
        assertEq(nft.ownerOf(tokenId), seller);
    }

    function test_TransferFrom_OperatorRoleDoesNotBypassOwnerApproval() public {
        uint256 tokenId = _mint(nft, seller);
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(ICustomNFT.NotAuthorized.selector, admin, tokenId));
        nft.transferFrom(seller, buyer, tokenId);
        assertEq(nft.ownerOf(tokenId), seller);
    }

    function test_Pause_BlocksMintTransferAndBurn() public {
        uint256 tokenId = _mint(nft, seller);
        vm.prank(admin);
        nft.pause();

        vm.prank(admin);
        vm.expectRevert();
        nft.mint(seller, "uri");

        vm.prank(seller);
        vm.expectRevert();
        nft.transferFrom(seller, buyer, tokenId);

        vm.prank(seller);
        vm.expectRevert();
        nft.burn(tokenId);

        vm.prank(admin);
        nft.unpause();
        vm.prank(seller);
        nft.transferFrom(seller, buyer, tokenId);
        assertEq(nft.ownerOf(tokenId), buyer);
    }

    function test_GrantAndRevokeMinter() public {
        vm.prank(admin);
        nft.grantMinter(buyer);
        vm.prank(buyer);
        nft.mint(seller, "uri");

        vm.prank(admin);
        nft.revokeMinter(buyer);
        vm.prank(buyer);
        vm.expectRevert();
        nft.mint(seller, "uri");
    }

    function test_SafeTransferFrom_ToEOASkipsReceiverCheck() public {
        uint256 tokenId = _mint(nft, seller);
        vm.prank(seller);
        nft.safeTransferFrom(seller, buyer, tokenId);
        assertEq(nft.ownerOf(tokenId), buyer);
    }

    function test_SetApprovalForAll_RevertsForSelfOperator() public {
        vm.prank(seller);
        vm.expectRevert(ICustomNFT.InvalidOperator.selector);
        nft.setApprovalForAll(seller, true);
    }

    function test_SupportsInterface_ReportsCustomNFTInterface() public view {
        assertTrue(nft.supportsInterface(type(ICustomNFT).interfaceId));
    }

    function test_ViewFunctions_ExistsApprovalForAllAndMintWindow() public {
        uint256 tokenId = _mint(nft, seller);
        assertTrue(nft.exists(tokenId));
        assertFalse(nft.exists(999));
        assertFalse(nft.isApprovedForAll(seller, buyer));
        vm.prank(seller);
        nft.setApprovalForAll(buyer, true);
        assertTrue(nft.isApprovedForAll(seller, buyer));
        vm.prank(seller);
        nft.setApprovalForAll(buyer, false);
        assertFalse(nft.isApprovedForAll(seller, buyer));

        (uint64 startBefore, uint64 endBefore) = nft.mintWindow();
        assertEq(startBefore, 0);
        assertEq(endBefore, 0);
        uint64 startAt = uint64(block.timestamp + 1 days);
        uint64 endAt = startAt + 1 days;
        vm.prank(admin);
        nft.setMintWindow(startAt, endAt);
        (uint64 startAfter, uint64 endAfter) = nft.mintWindow();
        assertEq(startAfter, startAt);
        assertEq(endAfter, endAt);

        vm.prank(seller);
        nft.burn(tokenId);
        assertFalse(nft.exists(tokenId));
    }
}

pragma solidity ^0.8.24;

import "../helpers/TestBase.sol";
import "../../src/interfaces/ICustomNFTReceiver.sol";

contract AcceptNFTReceiver is ICustomNFTReceiver {
    bool public called;
    address public operator;
    address public from;
    uint256 public tokenId;

    function onCustomNFTReceived(address operator_, address from_, uint256 tokenId_, bytes calldata)
        external
        returns (bytes4)
    {
        called = true;
        operator = operator_;
        from = from_;
        tokenId = tokenId_;
        return ICustomNFTReceiver.onCustomNFTReceived.selector;
    }
}

contract RejectNFTReceiver is ICustomNFTReceiver {
    function onCustomNFTReceived(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return bytes4(0);
    }
}

contract CustomNFTConformanceTest is ProtocolTestBase {
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
        string[] memory empty;
        vm.prank(admin);
        vm.expectRevert(ICustomNFT.BatchTooLarge.selector);
        nft.mintBatch(seller, empty);

        string[] memory uris = new string[](100);
        for (uint256 i; i < uris.length; ++i) uris[i] = "uri";
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
}

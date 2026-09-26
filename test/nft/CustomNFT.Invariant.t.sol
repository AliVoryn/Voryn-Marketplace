// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../support/TestBase.sol";

contract CustomNFTHandler is Test {
    CustomNFT internal nft;
    address internal admin;
    address[3] internal actors;

    uint256[] public mintedIds;
    uint256[] public burnedIds;

    constructor(CustomNFT nft_, address admin_, address[3] memory actors_) {
        nft = nft_;
        admin = admin_;
        actors = actors_;
    }

    function actorAt(uint256 index) external view returns (address) {
        return actors[index];
    }

    function mintedCount() external view returns (uint256) {
        return mintedIds.length;
    }

    function burnedCount() external view returns (uint256) {
        return burnedIds.length;
    }

    function mint(uint256 actorSeed) external {
        vm.prank(admin);
        uint256 id = nft.mint(actors[actorSeed % actors.length], "ipfs://invariant");
        mintedIds.push(id);
    }

    function transfer(uint256 idSeed, uint256 toSeed) external {
        if (mintedIds.length == 0) return;
        uint256 id = mintedIds[idSeed % mintedIds.length];
        address owner;
        try nft.ownerOf(id) returns (address current) {
            owner = current;
        } catch {
            return;
        }
        vm.prank(owner);
        try nft.transferFrom(owner, actors[toSeed % actors.length], id) { } catch { }
    }

    function burn(uint256 idSeed) external {
        if (mintedIds.length == 0) return;
        uint256 id = mintedIds[idSeed % mintedIds.length];
        address owner;
        try nft.ownerOf(id) returns (address current) {
            owner = current;
        } catch {
            return;
        }
        vm.prank(owner);
        try nft.burn(id) {
            burnedIds.push(id);
        } catch { }
    }
}

contract CustomNFTInvariantTest is ProtocolTestBase {
    CustomNFTHandler internal handler;

    function setUp() public {
        _setUpCore();
        address[3] memory actors = [seller, buyer, buyer2];
        handler = new CustomNFTHandler(nft, admin, actors);
        targetContract(address(handler));
    }

    function invariant_TotalSupplyEqualsSumOfBalances() public view {
        uint256 sum;
        for (uint256 i; i < 3; ++i) {
            sum += nft.balanceOf(handler.actorAt(i));
        }
        assertEq(sum, nft.totalSupply());
        assertEq(handler.mintedCount() - handler.burnedCount(), nft.totalSupply());
    }

    function invariant_EnumerationMatchesOwnership() public view {
        for (uint256 i; i < 3; ++i) {
            address actor = handler.actorAt(i);
            uint256[] memory owned = nft.tokensOfOwner(actor);
            assertEq(owned.length, nft.balanceOf(actor));
            for (uint256 j; j < owned.length; ++j) {
                assertEq(nft.ownerOf(owned[j]), actor);
                assertEq(uint8(nft.tokenState(owned[j])), uint8(ICustomNFT.TokenState.Minted));
            }
        }
    }

    function invariant_BurnedTokensAreTerminal() public view {
        uint256 count = handler.burnedCount();
        for (uint256 i; i < count; ++i) {
            uint256 id = handler.burnedIds(i);
            assertEq(uint8(nft.tokenState(id)), uint8(ICustomNFT.TokenState.Burned));
            assertFalse(nft.exists(id));
        }
    }
}

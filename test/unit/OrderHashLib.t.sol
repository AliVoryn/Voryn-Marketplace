pragma solidity ^0.8.24;
import "forge-std/Test.sol";
import "../../src/libraries/OrderHashLib.sol";
contract OrderHashLibTest is Test {
    function test_hashStruct_IsDeterministic() public pure {
        bytes32 h1 = OrderHashLib.hashStruct(address(1), address(2), 3, 4 ether, 5, 6);
        bytes32 h2 = OrderHashLib.hashStruct(address(1), address(2), 3, 4 ether, 5, 6);
        assertEq(h1, h2);
    }
    function test_hashStruct_EveryFieldChangesTheHash() public pure {
        bytes32 base = OrderHashLib.hashStruct(address(1), address(2), 3, 4 ether, 5, 6);
        assertTrue(base != OrderHashLib.hashStruct(address(9), address(2), 3, 4 ether, 5, 6), "seller");
        assertTrue(base != OrderHashLib.hashStruct(address(1), address(9), 3, 4 ether, 5, 6), "nft");
        assertTrue(base != OrderHashLib.hashStruct(address(1), address(2), 9, 4 ether, 5, 6), "tokenId");
        assertTrue(base != OrderHashLib.hashStruct(address(1), address(2), 3, 9 ether, 5, 6), "price");
        assertTrue(base != OrderHashLib.hashStruct(address(1), address(2), 3, 4 ether, 9, 6), "expiresAt");
        assertTrue(base != OrderHashLib.hashStruct(address(1), address(2), 3, 4 ether, 5, 9), "nonce");
    }
}

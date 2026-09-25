// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import { CustomNFT } from "../../core/CustomNFT.sol";

library NFTDeployer {
    function deploy(string memory name_, string memory symbol_, uint256 maxSupply_, address admin)
        external
        returns (address)
    {
        return address(new CustomNFT(name_, symbol_, maxSupply_, admin));
    }

    function deployDeterministic(
        string memory name_,
        string memory symbol_,
        uint256 maxSupply_,
        address admin,
        bytes32 salt
    ) external returns (address) {
        return address(new CustomNFT{ salt: salt }(name_, symbol_, maxSupply_, admin));
    }

    function initCodeHash(string memory name_, string memory symbol_, uint256 maxSupply_, address admin)
        external
        pure
        returns (bytes32)
    {
        return keccak256(abi.encodePacked(type(CustomNFT).creationCode, abi.encode(name_, symbol_, maxSupply_, admin)));
    }
}

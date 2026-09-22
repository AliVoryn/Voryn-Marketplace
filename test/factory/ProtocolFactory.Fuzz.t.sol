// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../support/TestBase.sol";

contract ProtocolFactoryFuzzTest is ProtocolTestBase {
    ProtocolFactory internal factory;

    function setUp() public {
        vm.prank(admin);
        factory = new ProtocolFactory(admin);
    }

    function testFuzz_DeterministicNFTPredictionIsStable(bytes32 salt) public {
        vm.assume(salt != bytes32(0));
        address predicted = factory.predictCustomNFTAddress(seller, "X", "X", 10, seller, salt);
        address predictedAgain = factory.predictCustomNFTAddress(seller, "X", "X", 10, seller, salt);
        assertEq(predicted, predictedAgain);
    }

    function testFuzz_SuiteCreationRejectsZeroAddresses(address admin_, address feeRecipient_) public {
        if (admin_ != address(0) && feeRecipient_ != address(0)) return;
        vm.prank(admin);
        vm.expectRevert(ProtocolFactory.ZeroAddress.selector);
        factory.createProtocolSuite(admin_, feeRecipient_);
    }
}

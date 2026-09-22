// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../support/TestBase.sol";

contract ProtocolFactoryRegressionTest is ProtocolTestBase {
    ProtocolFactory internal factory;

    function setUp() public {
        _setUpCore();
        vm.prank(admin);
        factory = new ProtocolFactory(admin);
    }

    function test_CreateBlindAuctionInstance_RequiresCallerIsBeneficiary() public {
        vm.prank(admin);
        address treasuryAddr = factory.createTreasury(feeRecipient);
        uint256 tokenId_ = _mint(nft, seller);
        vm.prank(seller);
        nft.setApprovalForAll(address(factory), true);
        vm.prank(attacker);
        vm.expectRevert(ProtocolFactory.NotSeller.selector);
        factory.createBlindAuctionInstance(
            attacker, payable(seller), address(nft), tokenId_, treasuryAddr, FEE_BPS, 1 days, 1 days, 0.01 ether
        );
    }

    function test_CreateBlindAuctionInstance_SucceedsWhenCallerIsBeneficiary() public {
        vm.prank(admin);
        address treasuryAddr = factory.createTreasury(feeRecipient);
        uint256 tokenId_ = _mint(nft, seller);
        vm.prank(seller);
        nft.setApprovalForAll(address(factory), true);
        vm.prank(seller);
        address auctionAddr = factory.createBlindAuctionInstance(
            seller, payable(seller), address(nft), tokenId_, treasuryAddr, FEE_BPS, 1 days, 1 days, 0.01 ether
        );
        assertEq(nft.ownerOf(tokenId_), auctionAddr);
    }
}

contract ProtocolFactoryTreasuryDrainRegressionTest is ProtocolTestBase {
    ProtocolFactory internal factory;
    address internal treasuryAddr;
    address internal pmAddr;

    function setUp() public {
        _setUpCore();
        vm.prank(admin);
        factory = new ProtocolFactory(admin);
        vm.startPrank(seller);
        treasuryAddr = factory.createTreasury(feeRecipient);
        pmAddr = factory.createPaymentManager();
        Ownable2Step(treasuryAddr).acceptOwnership();
        Ownable2Step(pmAddr).acceptOwnership();
        vm.stopPrank();
        vm.deal(address(this), 5 ether);
        (bool ok,) = treasuryAddr.call{ value: 5 ether }("");
        assertTrue(ok);
    }

    function test_ForeignCallerCannotObtainPayerRightsOnVictimTreasury() public {
        vm.startPrank(attacker);
        vm.expectRevert(ProtocolFactory.NotTreasuryAuthority.selector);
        factory.createStaking(treasuryAddr);
        vm.expectRevert(ProtocolFactory.NotTreasuryAuthority.selector);
        factory.createMarketplace(attacker, treasuryAddr, pmAddr);
        vm.stopPrank();
        assertEq(factory.creatorInstanceCount(attacker), 0);
        assertEq(Treasury(payable(treasuryAddr)).availableBalance(), 5 ether);
        assertEq(address(treasuryAddr).balance, 5 ether);
    }

    function test_TreasuryOwnerStillFundsStakingRewardsThroughFactoryInstance() public {
        vm.prank(seller);
        address stakingAddr = factory.createStaking(treasuryAddr);
        vm.prank(seller);
        Staking(payable(stakingAddr)).fundRewardsFromTreasury(5 ether);
        assertEq(address(stakingAddr).balance, 5 ether);
        assertEq(Treasury(payable(treasuryAddr)).availableBalance(), 0);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../support/TestBase.sol";

contract MarketplaceRegressionTest is ProtocolTestBase {
    Marketplace internal marketplace;
    uint256 internal signerPk = 0xA11CE;
    address internal signerSeller;

    function setUp() public {
        _setUpCore();
        marketplace = _deployMarketplaceProxy(address(treasury), address(paymentManager));
        signerSeller = vm.addr(signerPk);
    }

    function test_InvalidateNonce_IsCallableAndIncrementsNonce() public {
        assertEq(marketplace.nonceOf(signerSeller), 0);
        vm.prank(signerSeller);
        marketplace.invalidateNonce();
        assertEq(marketplace.nonceOf(signerSeller), 1);
    }
}

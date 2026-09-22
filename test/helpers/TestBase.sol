pragma solidity ^0.8.24;
import "forge-std/Test.sol";
import "../../src/core/Treasury.sol";
import "../../src/core/PaymentManager.sol";
import "../../src/core/CustomNFT.sol";
import "../../src/core/OpenAuction.sol";
import "../../src/core/BlindAuction.sol";
import "../../src/core/DutchAuction.sol";
import "../../src/core/Staking.sol";
import "../../src/core/Marketplace.sol";
import "../../src/core/Raffle.sol";
import "../../src/factory/ProtocolFactory.sol";
import "../../src/registries/ProtocolRegistry.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../mocks/MockVRFCoordinatorV2Plus.sol";
abstract contract ProtocolTestBase is Test {
    address internal admin = makeAddr("admin");
    address internal feeRecipient = makeAddr("feeRecipient");
    address internal seller = makeAddr("seller");
    address internal seller2 = makeAddr("seller2");
    address internal buyer = makeAddr("buyer");
    address internal buyer2 = makeAddr("buyer2");
    address internal attacker = makeAddr("attacker");
    Treasury internal treasury;
    PaymentManager internal paymentManager;
    CustomNFT internal nft;
    uint16 internal constant FEE_BPS = 250;
    function _deployTreasury() internal returns (Treasury t) {
        t = new Treasury(admin, feeRecipient);
    }
    function _deployPaymentManager() internal returns (PaymentManager pm) {
        pm = new PaymentManager(admin);
    }
    function _deployNFT() internal returns (CustomNFT n) {
        n = new CustomNFT("Test Collection", "TST", 10_000, admin);
    }
    function _mint(CustomNFT n, address to) internal returns (uint256 tokenId) {
        vm.prank(admin);
        tokenId = n.mint(to, "ipfs://token");
    }
    function _setUpCore() internal {
        treasury = _deployTreasury();
        paymentManager = _deployPaymentManager();
        nft = _deployNFT();
        vm.prank(admin);
        treasury.setAuthorizedPayer(admin, true); 
    }
    function _deployMarketplaceProxy(address treasury_, address paymentManager_) internal returns (Marketplace mp) {
        Marketplace impl = new Marketplace();
        bytes memory initData = abi.encodeCall(Marketplace.initialize, (admin, treasury_, paymentManager_));
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        mp = Marketplace(address(proxy));
    }
    function _deployOpenAuction(address treasury_) internal returns (OpenAuction oa) {
        oa = new OpenAuction(admin, treasury_, FEE_BPS);
    }
    function _deployDutchAuction(address treasury_) internal returns (DutchAuction da) {
        da = new DutchAuction(admin, treasury_, FEE_BPS);
    }
    function _deployStaking(address treasury_) internal returns (Staking st) {
        st = new Staking(admin, treasury_);
    }
    function _deployRaffle(address treasury_, MockVRFCoordinatorV2Plus coordinator)
        internal
        returns (Raffle rf)
    {
        rf = new Raffle(
            admin,
            treasury_,
            FEE_BPS,
            address(coordinator),
            1, 
            bytes32(uint256(1)), 
            200_000, 
            3, 
            false 
        );
    }
    function _deployMockCoordinator() internal returns (MockVRFCoordinatorV2Plus c) {
        c = new MockVRFCoordinatorV2Plus();
    }
}

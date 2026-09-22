// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./TestBase.sol";
import "../../src/automation/ProtocolAutomationReceiver.sol";

contract AutomationIntegrationForwarder { }

abstract contract AutomationIntegrationBase is ProtocolTestBase {
    uint64 internal constant CHAIN_SELECTOR = 16015286601757825753;
    bytes32 internal constant WORKFLOW_ID = keccak256("ali-voryn-automation");
    uint256 internal constant BLIND_BIDDING_TIME = 1 days;
    uint256 internal constant BLIND_REVEAL_TIME = 1 days;

    address internal workflowAuthor = makeAddr("workflow-author");

    ProtocolRegistry internal registry;
    ProtocolAutomationReceiver internal receiver;
    AutomationIntegrationForwarder internal forwarder;
    MockVRFCoordinatorV2Plus internal coordinator;

    OpenAuction internal openAuction;
    DutchAuction internal dutchAuction;
    BlindAuction internal blindAuction;
    Marketplace internal marketplace;
    Raffle internal raffle;

    function setUp() public virtual {
        _setUpCore();
        registry = new ProtocolRegistry(admin);
        forwarder = new AutomationIntegrationForwarder();
        receiver = new ProtocolAutomationReceiver(admin, address(forwarder), address(registry), CHAIN_SELECTOR);
        coordinator = _deployMockCoordinator();

        openAuction = _deployOpenAuction(address(treasury));
        dutchAuction = _deployDutchAuction(address(treasury));
        marketplace = _deployMarketplaceProxy(address(treasury), address(paymentManager));
        raffle = _deployRaffle(address(treasury), coordinator);

        uint256 blindTokenId = _mint(nft, seller);
        blindAuction = new BlindAuction(
            admin,
            payable(seller),
            address(nft),
            blindTokenId,
            address(treasury),
            FEE_BPS,
            BLIND_BIDDING_TIME,
            BLIND_REVEAL_TIME,
            1 ether
        );
        vm.prank(seller);
        nft.approve(address(this), blindTokenId);
        nft.transferFrom(seller, address(blindAuction), blindTokenId);

        vm.startPrank(admin);
        treasury.setAuthorizedPayer(address(openAuction), true);
        treasury.setAuthorizedPayer(address(dutchAuction), true);
        treasury.setAuthorizedPayer(address(blindAuction), true);
        treasury.setAuthorizedPayer(address(marketplace), true);
        treasury.setAuthorizedPayer(address(raffle), true);
        paymentManager.setCreditor(address(marketplace), true);

        registry.registerInstance(address(openAuction), seller, address(0), keccak256("OPEN_AUCTION"), 1);
        registry.registerInstance(address(blindAuction), seller, address(0), keccak256("BLIND_AUCTION"), 1);
        registry.registerInstance(address(dutchAuction), seller, address(0), keccak256("DUTCH_AUCTION"), 1);
        registry.registerInstance(address(marketplace), seller, address(0), keccak256("MARKETPLACE"), 1);
        registry.registerInstance(address(raffle), seller, address(0), keccak256("RAFFLE"), 1);

        receiver.setExpectedWorkflowId(WORKFLOW_ID);
        receiver.setExpectedAuthor(workflowAuthor);
        receiver.unpauseAutomation();
        vm.stopPrank();
    }

    function _metadata() internal view returns (bytes memory) {
        return abi.encodePacked(WORKFLOW_ID, bytes10(0), workflowAuthor, bytes2(0));
    }

    function _encode(
        ProtocolAutomationReceiver.Action action,
        address instance,
        uint256 id,
        uint256 value,
        uint256 cursor
    ) internal view returns (bytes memory) {
        return abi.encode(action, instance, id, value, cursor, uint64(block.timestamp), CHAIN_SELECTOR);
    }

    function _deliver(
        ProtocolAutomationReceiver.Action action,
        address instance,
        uint256 id,
        uint256 value,
        uint256 cursor
    ) internal {
        vm.prank(address(forwarder));
        receiver.onReport(_metadata(), _encode(action, instance, id, value, cursor));
    }

    function _mintApproved(address to, address operator) internal returns (uint256 tokenId) {
        tokenId = _mint(nft, to);
        vm.prank(to);
        nft.approve(operator, tokenId);
    }
}

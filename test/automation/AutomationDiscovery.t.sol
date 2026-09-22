// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../support/AutomationIntegrationBase.sol";
import "../../src/libraries/AutomationScanLib.sol";

contract ScanLibHarness {
    function window(uint256 total, uint256 cycle, uint256 maxScan) external pure returns (uint256, uint256) {
        return AutomationScanLib.window(total, cycle, maxScan);
    }

    function capacity(uint256 maxItems, uint256 startId, uint256 endId) external pure returns (uint256) {
        return AutomationScanLib.capacity(maxItems, startId, endId);
    }
}

contract DummyInstance { }

contract AutomationDiscoveryTest is AutomationIntegrationBase {
    ScanLibHarness internal harness;

    uint256 internal openNextSlot;
    uint256 internal dutchNextSlot;
    uint256 internal marketNextSlot;
    uint256 internal raffleNextSlot;

    function setUp() public override {
        super.setUp();
        harness = new ScanLibHarness();
        openNextSlot = _findCounterSlot(address(openAuction), abi.encodeWithSignature("nextAuctionId()"), 0);
        dutchNextSlot = _findCounterSlot(address(dutchAuction), abi.encodeWithSignature("nextAuctionId()"), 0);
        marketNextSlot = _findCounterSlot(address(marketplace), abi.encodeCall(Marketplace.offerCount, ()), 0);
        raffleNextSlot = _findCounterSlot(address(raffle), abi.encodeCall(Raffle.raffleCount, ()), 1);
    }

    function _findCounterSlot(address target, bytes memory getter, uint256 getterOffset) internal returns (uint256) {
        uint256 sentinel = 0xC0FFEE0000000000000000000000000000000000000000000000000000000001;
        for (uint256 slot; slot < 120; ++slot) {
            bytes32 original = vm.load(target, bytes32(slot));
            vm.store(target, bytes32(slot), bytes32(sentinel));
            (bool ok, bytes memory ret) = target.staticcall(getter);
            vm.store(target, bytes32(slot), original);
            if (ok && ret.length == 32 && abi.decode(ret, (uint256)) == sentinel - getterOffset) return slot;
        }
        revert("counter slot not found");
    }

    function test_WindowsCoverEveryIdExactlyOnce() public view {
        uint256[5] memory totals = [uint256(1), 7, 250, 251, 1234];
        uint256[5] memory scans = [uint256(1), 3, 250, 500, 100_000];
        for (uint256 t = 0; t < totals.length; ++t) {
            for (uint256 s = 0; s < scans.length; ++s) {
                uint256 total = totals[t];
                uint256 span = scans[s] > 500 ? 500 : scans[s];
                if (span > total) span = total;
                uint256 windows = (total + span - 1) / span;
                uint256 next = 1;
                for (uint256 c = 0; c < windows; ++c) {
                    (uint256 a, uint256 b) = harness.window(total, c, scans[s]);
                    assertEq(a, next, "windows must be consecutive");
                    assertLe(b - a, 500, "hard scan cap");
                    assertLe(b - a, scans[s], "caller scan cap");
                    next = b;
                }
                assertEq(next, total + 1, "every id covered");

                (uint256 a0,) = harness.window(total, 0, scans[s]);
                (uint256 aw,) = harness.window(total, windows, scans[s]);
                assertEq(a0, aw);
            }
        }
    }

    function test_WindowIsEmptyForNoIdsOrZeroScan() public view {
        (uint256 a, uint256 b) = harness.window(0, 5, 100);
        assertEq(a, b);
        (a, b) = harness.window(10, 5, 0);
        assertEq(a, b);
    }

    function _gasOf(address target, bytes memory data) internal returns (uint256 used) {
        vm.cool(target);
        uint256 g = gasleft();
        (bool ok,) = target.staticcall(data);
        used = g - gasleft();
        assertTrue(ok);
    }

    function test_OpenAuctionScanCostIndependentOfTotalIds() public {
        bytes memory data = abi.encodeCall(OpenAuction.automationDueIds, (0, 250, 25));
        vm.store(address(openAuction), bytes32(openNextSlot), bytes32(uint256(1_001)));
        uint256 small = _gasOf(address(openAuction), data);
        vm.store(address(openAuction), bytes32(openNextSlot), bytes32(uint256(1_000_001)));
        uint256 huge = _gasOf(address(openAuction), data);
        assertLt(huge, small + small / 10, "1M ids must cost about the same as 1k ids");
        assertLt(huge, 2_000_000);
    }

    function test_AllFourViewsStayBoundedWithAMillionIds() public {
        vm.store(address(openAuction), bytes32(openNextSlot), bytes32(uint256(1_000_001)));
        vm.store(address(dutchAuction), bytes32(dutchNextSlot), bytes32(uint256(1_000_001)));
        vm.store(address(marketplace), bytes32(marketNextSlot), bytes32(uint256(1_000_000)));
        vm.store(address(raffle), bytes32(raffleNextSlot), bytes32(uint256(1_000_001)));

        uint256 gOpen = _gasOf(
            address(openAuction),
            abi.encodeCall(OpenAuction.automationDueIds, (7, type(uint256).max, type(uint256).max))
        );
        uint256 gDutch = _gasOf(
            address(dutchAuction),
            abi.encodeCall(DutchAuction.automationDueIds, (7, type(uint256).max, type(uint256).max))
        );
        uint256 gMarket = _gasOf(
            address(marketplace),
            abi.encodeCall(Marketplace.automationDueOfferIds, (7, type(uint256).max, type(uint256).max))
        );
        uint256 gRaffle = _gasOf(
            address(raffle), abi.encodeCall(Raffle.automationCandidates, (7, type(uint256).max, type(uint256).max))
        );
        emit log_named_uint("gas open (1M ids, clamped)", gOpen);
        emit log_named_uint("gas dutch", gDutch);
        emit log_named_uint("gas marketplace", gMarket);
        emit log_named_uint("gas raffle", gRaffle);
        assertLt(gOpen, 3_000_000);
        assertLt(gDutch, 3_000_000);
        assertLt(gMarket, 3_000_000);
        assertLt(gRaffle, 6_000_000);
    }

    function test_SparseDueItemInLargeRangeIsFoundInItsWindowOnly() public {
        uint256 t1 = _mintApproved(seller, address(openAuction));
        vm.prank(seller);
        uint256 id = openAuction.createAuction(address(nft), t1, 1 ether, 0.1 ether, 0, 1 days);
        vm.store(address(openAuction), bytes32(openNextSlot), bytes32(uint256(1_000_001)));
        vm.warp(block.timestamp + 1 days + 1);

        assertEq(openAuction.automationDueIds(0, 250, 25).length, 1, "id 1 sits in window 0");
        assertEq(openAuction.automationDueIds(0, 250, 25)[0], id);
        assertEq(openAuction.automationDueIds(1, 250, 25).length, 0, "window 1 does not contain it");
    }

    function test_OfferRotationFindsAllDueOffersAndMaxItemsCapsResults() public {
        uint256 tokenId = _mint(nft, seller);
        uint256[] memory ids = new uint256[](12);
        for (uint256 i = 0; i < 12; ++i) {
            address b = makeAddr(string(abi.encodePacked("offerer", i)));
            vm.deal(b, 1 ether);
            vm.prank(b);
            ids[i] = marketplace.makeOffer{ value: 1 ether }(address(nft), tokenId, uint64(block.timestamp + 1 days));
        }
        vm.warp(block.timestamp + 1 days);

        bool[13] memory seen;
        uint256 total;

        for (uint256 cycle = 0; cycle < 3; ++cycle) {
            uint256[] memory due = marketplace.automationDueOfferIds(cycle, 5, 100);
            assertLe(due.length, 5, "never more than one window");
            for (uint256 k = 0; k < due.length; ++k) {
                assertFalse(seen[due[k]], "no id reported by two windows");
                seen[due[k]] = true;
                ++total;
            }
        }
        assertEq(total, 12);
        assertEq(marketplace.automationDueOfferIds(0, 5, 2).length, 2, "maxItems caps results");
        assertEq(marketplace.automationDueOfferIds(0, 5, 0).length, 0);
        assertEq(marketplace.automationDueOfferIds(0, 0, 5).length, 0);
    }

    function test_OpenAndDutchAndRaffleRotationCoverAllIds() public {
        for (uint256 i = 0; i < 6; ++i) {
            uint256 a = _mintApproved(seller, address(openAuction));
            uint256 d = _mintApproved(seller, address(dutchAuction));
            uint256 r = _mintApproved(seller, address(raffle));
            vm.startPrank(seller);
            openAuction.createAuction(address(nft), a, 1 ether, 0.1 ether, 0, 1 days);
            dutchAuction.createAuction(address(nft), d, 2 ether, 1 ether, 0, 1 days);
            raffle.createRaffle(address(nft), r, 1 ether, 10, 10, 0, 1 days);
            vm.stopPrank();
        }
        vm.warp(block.timestamp + 1 days + 1);

        uint256 openTotal;
        uint256 dutchTotal;
        uint256 raffleTotal;

        for (uint256 cycle = 0; cycle < 3; ++cycle) {
            openTotal += openAuction.automationDueIds(cycle, 2, 100).length;
            dutchTotal += dutchAuction.automationDueIds(cycle, 2, 100).length;
            (, uint256[] memory failed,) = raffle.automationCandidates(cycle, 2, 100);
            raffleTotal += failed.length;
        }
        assertEq(openTotal, 6);
        assertEq(dutchTotal, 6);
        assertEq(raffleTotal, 6);
    }

    function test_RegistryCycleAdvancesOncePerFullPassForAnyPartitionCount() public {
        bytes32 kind = keccak256("DUMMY_KIND");
        address[] memory inst = new address[](5);
        vm.startPrank(admin);
        for (uint256 i = 0; i < 5; ++i) {
            inst[i] = address(new DummyInstance());
            registry.registerInstance(inst[i], seller, address(0), kind, 1);
        }
        vm.stopPrank();

        uint256[3] memory partitionCounts = [uint256(1), 2, 5];
        for (uint256 pc = 0; pc < partitionCounts.length; ++pc) {
            uint256 stride = partitionCounts[pc];
            uint256[5] memory lastCycle;
            bool[5] memory visited;
            uint256 visitsSeen;
            for (uint256 slot = 0; slot < 20; ++slot) {
                for (uint256 p = 0; p < stride; ++p) {
                    (address[] memory got, uint256 cycle) =
                        registry.automationInstancesWithCycle(kind, slot * stride + p, 1);
                    assertEq(got.length, 1);
                    uint256 idx = (slot * stride + p) % 5;
                    assertEq(got[0], inst[idx]);
                    if (visited[idx]) assertEq(cycle, lastCycle[idx] + 1, "cycle +1 per visit");
                    visited[idx] = true;
                    lastCycle[idx] = cycle;
                    ++visitsSeen;
                }
            }
            assertEq(visitsSeen, 20 * stride);
        }
    }

    function test_CapacityIsClampedToWindowAndHardItemCap() public view {
        assertEq(harness.capacity(type(uint256).max, 1, 501), 100);
        assertEq(harness.capacity(1000, 1, 11), 10);
        assertEq(harness.capacity(3, 1, 500), 3);
        assertEq(harness.capacity(0, 1, 500), 0);
    }

    function test_PausedContractsReturnNoCandidates() public {
        uint256 tokenId = _mintApproved(seller, address(raffle));
        vm.prank(seller);
        raffle.createRaffle(address(nft), tokenId, 1 ether, 10, 10, 0, 1 days);
        uint256 offerToken = _mint(nft, seller);
        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        marketplace.makeOffer{ value: 1 ether }(address(nft), offerToken, uint64(block.timestamp + 1 days));
        vm.warp(block.timestamp + 1 days + 1);

        (, uint256[] memory failedBefore,) = raffle.automationCandidates(0, 10, 10);
        assertEq(failedBefore.length, 1);
        assertEq(marketplace.automationDueOfferIds(0, 10, 10).length, 1);

        vm.startPrank(admin);
        raffle.pause();
        marketplace.pause();
        openAuction.pause();
        dutchAuction.pause();
        vm.stopPrank();

        (uint256[] memory w, uint256[] memory f, Raffle.AutomationRefundCandidate[] memory r) =
            raffle.automationCandidates(0, 10, 10);
        assertEq(w.length + f.length + r.length, 0);
        assertEq(marketplace.automationDueOfferIds(0, 10, 10).length, 0);
        assertEq(openAuction.automationDueIds(0, 10, 10).length, 0);
        assertEq(dutchAuction.automationDueIds(0, 10, 10).length, 0);
    }

    function test_RegistryPageSkipsInactiveInstancesAndHandlesEmptyKinds() public {
        bytes32 kind = keccak256("SKIP_KIND");
        address a = address(new DummyInstance());
        address b = address(new DummyInstance());
        vm.startPrank(admin);
        registry.registerInstance(a, seller, address(0), kind, 1);
        registry.registerInstance(b, seller, address(0), kind, 1);
        registry.setActive(a, false);
        vm.stopPrank();

        (address[] memory page, uint256 cycle) = registry.automationInstancesWithCycle(kind, 0, 2);
        assertEq(page.length, 1);
        assertEq(page[0], b);
        assertEq(cycle, 0);

        (page, cycle) = registry.automationInstancesWithCycle(keccak256("NO_SUCH_KIND"), 12345, 3);
        assertEq(page.length, 0);
        assertEq(cycle, 0);

        (page, cycle) = registry.automationInstancesWithCycle(kind, 5, 0);
        assertEq(page.length, 0);
        assertEq(registry.automationInstances(kind, 1, 1).length, 1);
    }
}

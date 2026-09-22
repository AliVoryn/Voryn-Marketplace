

import test from "node:test";
import assert from "node:assert/strict";
import {
  ACTION, KINDS, discoveryOffset, kindOrder, runAutomation,
  type Address, type AutomationIO, type AutomationLimits, type Kind, type RaffleCandidates, type ReportAction,
} from "./automation.ts";
import { encodeReport } from "./report.ts";

const addr = (n: number): Address => `0x${n.toString(16).padStart(40, "0")}`;
const MAX_SCAN = 500n;

const LIMITS: AutomationLimits = {
  instancesPerKindPerRun: 1, maxIdsPerInstance: 25, maxScanPerInstance: 250, maxReportsPerRun: 10,
  refundBatchSize: 12, partitionCount: 1, partitionIndex: 0,
};

function window(total: bigint, cycle: bigint, maxScan: bigint): [bigint, bigint] {
  if (total === 0n || maxScan === 0n) return [1n, 1n];
  if (maxScan > MAX_SCAN) maxScan = MAX_SCAN;
  const span = total < maxScan ? total : maxScan;
  const windows = (total + span - 1n) / span;
  const start = 1n + (cycle % windows) * span;
  let end = start + span;
  if (end > total + 1n) end = total + 1n;
  return [start, end];
}

interface FakeChain {
  instances: Record<Kind, Address[]>;
  total: Record<string, bigint>;
  due: Record<string, Set<bigint>>;
  blindReady: Set<string>;
  raffle: Record<string, RaffleCandidates & { all?: never }>;
  paused: boolean;
  failWrites: boolean;
  inspected: number;
  writes: ReportAction[];
  visited: Array<{ kind: Kind; instance: Address; cycle: bigint }>;
}

function fakeChain(partial: Partial<FakeChain> = {}): FakeChain {
  return {
    instances: { OPEN_AUCTION: [], BLIND_AUCTION: [], DUTCH_AUCTION: [], MARKETPLACE: [], RAFFLE: [] },
    total: {}, due: {}, blindReady: new Set(), raffle: {}, paused: false, failWrites: false,
    inspected: 0, writes: [], visited: [], ...partial,
  };
}

function ioFor(c: FakeChain): AutomationIO {
  return {
    isPaused: () => c.paused,
    instances: (kind, offset, limit) => {
      const list = c.instances[kind];
      if (list.length === 0) return { instances: [], cycle: 0n };
      const count = BigInt(list.length);
      const cycle = offset / count;
      const start = Number(offset % count);
      const page = list.slice(start, start + limit);
      for (const instance of page) c.visited.push({ kind, instance, cycle });
      return { instances: page, cycle };
    },
    dueIds: (_kind, instance, cycle, maxScan, maxItems) => {
      const [s, e] = window(c.total[instance] ?? 0n, cycle, maxScan);
      const out: bigint[] = [];
      for (let id = s; id < e && BigInt(out.length) < maxItems; id++) {
        c.inspected++;
        if (c.due[instance]?.has(id)) out.push(id);
      }
      return out;
    },
    blindReady: (instance) => c.blindReady.has(instance),
    raffleCandidates: (instance) => c.raffle[instance] ?? { winnerRequestIds: [], failedIds: [], refundCandidates: [] },
    write: (a) => {
      if (c.failWrites) return false;
      c.writes.push(a);
      return true;
    },
    log: () => {},
  };
}

test("discoveryOffset: stride = partitionCount, start offset = partitionIndex, inputs validated", () => {
  assert.equal(discoveryOffset(120n, 1, 0), 2n);
  assert.equal(discoveryOffset(120n, 25, 0), 50n);
  assert.equal(discoveryOffset(120n, 25, 7), 57n);
  assert.equal(discoveryOffset(179n, 4, 3), 2n * 4n + 3n);
  assert.throws(() => discoveryOffset(0n, 0, 0));
  assert.throws(() => discoveryOffset(0n, 4, 4));
  assert.throws(() => discoveryOffset(0n, 4, -1));
});

test("rotation latency: 250 instances, 1 per minute => 250 min; 25 partitions => 10 min", () => {
  const revisit = (partitions: number) => {
    const list = Array.from({ length: 250 }, (_, i) => addr(i + 1));
    const lastSeen = new Map<Address, number>();
    let maxGap = 0;
    for (let minute = 0; minute < 600; minute++) {
      for (let p = 0; p < partitions; p++) {
        const off = discoveryOffset(BigInt(minute * 60), partitions, p);
        const inst = list[Number(off % 250n)];
        if (lastSeen.has(inst)) maxGap = Math.max(maxGap, minute - lastSeen.get(inst)!);
        lastSeen.set(inst, minute);
      }
    }
    return maxGap;
  };
  assert.equal(revisit(1), 250);
  assert.equal(revisit(25), 10);
  assert.equal(revisit(50), 5);
});

test("every registry position is used by exactly one (minute, partition) pair", () => {
  const seen = new Set<bigint>();
  for (let minute = 0; minute < 40; minute++)
    for (let p = 0; p < 5; p++) {
      const off = discoveryOffset(BigInt(minute * 60), 5, p);
      assert.ok(!seen.has(off));
      seen.add(off);
    }
  assert.equal(seen.size, 200);
});

test("runAutomation emits the right action for every kind, with refund batch size and cursor", () => {
  const c = fakeChain();
  const [o, b, d, m, r] = [addr(1), addr(2), addr(3), addr(4), addr(5)];
  c.instances = { OPEN_AUCTION: [o], BLIND_AUCTION: [b], DUTCH_AUCTION: [d], MARKETPLACE: [m], RAFFLE: [r] };
  c.total = { [o]: 10n, [d]: 10n, [m]: 10n };
  c.due = { [o]: new Set([3n]), [d]: new Set([4n, 5n]), [m]: new Set([9n]) };
  c.blindReady.add(b);
  c.raffle[r] = { winnerRequestIds: [1n], failedIds: [2n], refundCandidates: [{ raffleId: 7n, cursor: 24n }] };

  const n = runAutomation(ioFor(c), LIMITS, 600n);
  assert.equal(n, 8);
  assert.deepEqual(
    c.writes.map((w) => [w.action, w.instance, w.id, w.value, w.cursor]),
    [
      [ACTION.FINALIZE_OPEN_AUCTION, o, 3n, 0n, 0n],
      [ACTION.FINALIZE_BLIND_AUCTION, b, 0n, 0n, 0n],
      [ACTION.EXPIRE_DUTCH_AUCTION, d, 4n, 0n, 0n],
      [ACTION.EXPIRE_DUTCH_AUCTION, d, 5n, 0n, 0n],
      [ACTION.EXPIRE_OFFER, m, 9n, 0n, 0n],
      [ACTION.REQUEST_RAFFLE_WINNER, r, 1n, 0n, 0n],
      [ACTION.FINALIZE_FAILED_RAFFLE, r, 2n, 0n, 0n],
      [ACTION.PROCESS_RAFFLE_REFUNDS, r, 7n, 12n, 24n],
    ],
  );
});

test("runAutomation: paused receiver => no reads of instances, no writes", () => {
  const c = fakeChain({ paused: true });
  c.instances.OPEN_AUCTION = [addr(1)];
  assert.equal(runAutomation(ioFor(c), LIMITS, 60n), 0);
  assert.equal(c.visited.length, 0);
});

test("runAutomation: failed writes are not counted as success", () => {
  const c = fakeChain({ failWrites: true });
  c.instances.BLIND_AUCTION = [addr(2)];
  c.blindReady.add(addr(2));
  assert.equal(runAutomation(ioFor(c), LIMITS, 60n), 0);
});

test("runAutomation: maxReportsPerRun is a hard cap", () => {
  const c = fakeChain();
  const o = addr(1);
  c.instances.OPEN_AUCTION = [o];
  c.total = { [o]: 100n };
  c.due = { [o]: new Set(Array.from({ length: 30 }, (_, i) => BigInt(i + 1))) };
  assert.equal(runAutomation(ioFor(c), { ...LIMITS, maxReportsPerRun: 4 }, 60n), 4);
});

test("bounded discovery: 1,000,000 ids never inspect more than maxScan ids per call, rotation reaches every due id", () => {
  const c = fakeChain();
  const o = addr(1);
  c.instances.OPEN_AUCTION = [o];
  c.total = { [o]: 1_000_000n };
  const target = new Set([5n, 300_000n, 999_999n]);
  c.due = { [o]: target };

  const found = new Set<bigint>();
  let calls = 0;

  for (let minute = 0; minute < 4000 && found.size < target.size; minute++) {
    const before = c.inspected;
    runAutomation(ioFor(c), LIMITS, BigInt(minute * 60));
    assert.ok(c.inspected - before <= 250, "per-execution scan is bounded by maxScanPerInstance");
    calls++;
    for (const w of c.writes) found.add(w.id);
  }
  assert.deepEqual(found, target);
  assert.ok(calls <= 4000);
});

test("kinds are visited in a rotating order and cycle comes from the registry page", () => {
  const c = fakeChain();
  for (const k of KINDS) c.instances[k] = [addr(1), addr(2)];
  runAutomation(ioFor(c), LIMITS, 5n * 60n);
  assert.deepEqual(c.visited.map((v) => v.kind), kindOrder(5n * 60n));
  assert.ok(c.visited.every((v) => v.instance === addr(2) && v.cycle === 2n));
  const firsts = new Set(Array.from({ length: 5 }, (_, i) => kindOrder(BigInt(i * 60))[0]));
  assert.equal(firsts.size, 5);
  for (let i = 0; i < 5; i++) assert.deepEqual([...kindOrder(BigInt(i * 60))].sort(), [...KINDS].sort());
});

test("no kind is starved when earlier kinds saturate maxReportsPerRun", () => {
  const c = fakeChain();
  const [o, d, m, r] = [addr(1), addr(3), addr(4), addr(5)];
  const ids = new Set(Array.from({ length: 40 }, (_, i) => BigInt(i + 1)));
  c.instances = { OPEN_AUCTION: [o], BLIND_AUCTION: [], DUTCH_AUCTION: [d], MARKETPLACE: [m], RAFFLE: [r] };
  c.total = { [o]: 40n, [d]: 40n, [m]: 40n };
  c.due = { [o]: ids, [d]: ids, [m]: ids };
  c.raffle[r] = { winnerRequestIds: [1n], failedIds: [], refundCandidates: [] };
  const served = new Set<number>();
  for (let minute = 0; minute < 5; minute++) {
    c.writes = [];
    runAutomation(ioFor(c), { ...LIMITS, maxReportsPerRun: 3, maxIdsPerInstance: 10 }, BigInt(minute * 60));
    for (const w of c.writes) served.add(w.action);
  }
  assert.ok(served.has(ACTION.FINALIZE_OPEN_AUCTION));
  assert.ok(served.has(ACTION.EXPIRE_DUTCH_AUCTION));
  assert.ok(served.has(ACTION.EXPIRE_OFFER));
  assert.ok(served.has(ACTION.REQUEST_RAFFLE_WINNER));
});

test("registry growing mid-run only delays discovery and never loses a due id", () => {
  const c = fakeChain();
  const [a1, a2, a3] = [addr(1), addr(2), addr(3)];
  c.instances.OPEN_AUCTION = [a1, a2];
  c.total = { [a1]: 900n, [a2]: 900n, [a3]: 900n };
  const wanted = new Map<Address, bigint>([[a1, 850n], [a2, 3n], [a3, 500n]]);
  c.due = { [a1]: new Set([850n]), [a2]: new Set([3n]), [a3]: new Set([500n]) };
  const found = new Set<string>();
  for (let minute = 0; minute < 400 && found.size < 3; minute++) {
    if (minute === 7) c.instances.OPEN_AUCTION = [a1, a2, a3];
    c.writes = [];
    runAutomation(ioFor(c), LIMITS, BigInt(minute * 60));
    for (const w of c.writes) found.add(`${w.instance}:${w.id}`);
  }
  assert.deepEqual([...found].sort(), [...wanted].map(([k, v]) => `${k}:${v}`).sort());
});

test("more partitions than instances only produces duplicate visits, never a missed instance", () => {
  const list = [addr(1), addr(2), addr(3)];
  const visits = new Map<Address, number>();
  for (let minute = 0; minute < 10; minute++)
    for (let p = 0; p < 7; p++) {
      const inst = list[Number(discoveryOffset(BigInt(minute * 60), 7, p) % 3n)];
      visits.set(inst, (visits.get(inst) ?? 0) + 1);
    }
  assert.equal(visits.size, 3);
  assert.equal([...visits.values()].reduce((x, y) => x + y, 0), 70);
});

test("encodeReport matches the 224-byte ABI layout the receiver decodes (vector from `cast abi-encode`)", () => {
  const hex = encodeReport(
    { action: ACTION.PROCESS_RAFFLE_REFUNDS, instance: addr(0xaa), id: 7n, value: 12n, cursor: 3n },
    1700000060n, 16015286601757825753n,
  );
  assert.equal(
    hex,
    "0x000000000000000000000000000000000000000000000000000000000000000500000000000000000000000000000000000000000000000000000000000000aa0000000000000000000000000000000000000000000000000000000000000007000000000000000000000000000000000000000000000000000000000000000c0000000000000000000000000000000000000000000000000000000000000003000000000000000000000000000000000000000000000000000000006553f13c000000000000000000000000000000000000000000000000de41ba4fc9d91ad9",
  );
  assert.equal((hex.length - 2) / 2, 224);
});

import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { configSchema } from "./config.ts";

const REG = "0x" + "1".repeat(40);
const RCV = "0x" + "2".repeat(40);

function load(name: string) {
  const raw = JSON.parse(readFileSync(new URL(`./${name}`, import.meta.url), "utf8"));
  for (const e of raw.evms) {
    e.registryAddress = REG;
    e.receiverAddress = RCV;
  }
  return raw;
}

for (const name of ["config.staging.json", "config.production.json", "config.simulation.json"]) {
  test(`${name} satisfies the workflow config schema once addresses are filled in`, () => {
    const parsed = configSchema.parse(load(name));
    assert.equal(parsed.evms[0].instancesPerKindPerRun, 1);
    assert.equal(parsed.evms[0].partitionCount, 1);
    assert.equal(parsed.evms[0].partitionIndex, 0);
    assert.equal(parsed.evms[0].refundBatchSize, 12);
    assert.equal(parsed.evms[0].gasLimit, "1000000");
  });
}

test("placeholder addresses are rejected until replaced", () => {
  const raw = JSON.parse(readFileSync(new URL("./config.staging.json", import.meta.url), "utf8"));
  assert.throws(() => configSchema.parse(raw));
});

test("partition, scan and refund bounds are enforced", () => {
  const base = load("config.staging.json");
  const withEvm = (patch: Record<string, unknown>) => ({ ...base, evms: [{ ...base.evms[0], ...patch }] });
  assert.throws(() => configSchema.parse(withEvm({ partitionIndex: 1 })));
  assert.doesNotThrow(() => configSchema.parse(withEvm({ partitionCount: 4, partitionIndex: 3 })));
  assert.throws(() => configSchema.parse(withEvm({ partitionCount: 4, partitionIndex: 4 })));
  assert.throws(() => configSchema.parse(withEvm({ maxScanPerInstance: 501 })));
  assert.throws(() => configSchema.parse(withEvm({ maxScanPerInstance: 0 })));
  assert.throws(() => configSchema.parse(withEvm({ refundBatchSize: 101 })));
  assert.throws(() => configSchema.parse(withEvm({ instancesPerKindPerRun: 2 })));
  assert.throws(() => configSchema.parse(withEvm({ maxIdsPerInstance: 101 })));
});

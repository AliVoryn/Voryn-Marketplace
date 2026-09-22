import {
  Runner,
  type CronPayload,
  type Runtime,
  bytesToHex,
  cre,
  encodeCallMsg,
  getNetwork,
  LAST_FINALIZED_BLOCK_NUMBER,
  prepareReportRequest,
  TxStatus,
} from "@chainlink/cre-sdk";
import type { Abi, Address } from "viem";
import { decodeFunctionResult, encodeFunctionData, keccak256, stringToHex, zeroAddress } from "viem";
import { runAutomation, type AutomationIO, type Kind, type RaffleCandidates } from "./automation.ts";
import { encodeReport } from "./report.ts";
import { configSchema, type Config } from "./config.ts";
type EVM = InstanceType<typeof cre.capabilities.EVMClient>;

const registryAbi = [{
  type: "function", name: "automationInstancesWithCycle", stateMutability: "view",
  inputs: [
    { name: "kind", type: "bytes32" },
    { name: "offset", type: "uint256" },
    { name: "limit", type: "uint256" },
  ],
  outputs: [
    { name: "instances", type: "address[]" },
    { name: "cycle", type: "uint256" },
  ],
}] as const satisfies Abi;

const receiverAbi = [
  { type: "function", name: "paused", stateMutability: "view", inputs: [], outputs: [{ name: "", type: "bool" }] },
] as const satisfies Abi;

const openAbi = [{
  type: "function", name: "automationDueIds", stateMutability: "view",
  inputs: [
    { name: "cycle", type: "uint256" },
    { name: "maxScan", type: "uint256" },
    { name: "maxItems", type: "uint256" },
  ],
  outputs: [{ name: "dueIds", type: "uint256[]" }],
}] as const satisfies Abi;

const blindAbi = [{
  type: "function", name: "automationReady", stateMutability: "view", inputs: [], outputs: [{ name: "", type: "bool" }],
}] as const satisfies Abi;

const dutchAbi = [{
  type: "function", name: "automationDueIds", stateMutability: "view",
  inputs: [
    { name: "cycle", type: "uint256" },
    { name: "maxScan", type: "uint256" },
    { name: "maxItems", type: "uint256" },
  ],
  outputs: [{ name: "dueIds", type: "uint256[]" }],
}] as const satisfies Abi;

const marketplaceAbi = [{
  type: "function", name: "automationDueOfferIds", stateMutability: "view",
  inputs: [
    { name: "cycle", type: "uint256" },
    { name: "maxScan", type: "uint256" },
    { name: "maxItems", type: "uint256" },
  ],
  outputs: [{ name: "dueIds", type: "uint256[]" }],
}] as const satisfies Abi;

const raffleAbi = [{
  type: "function", name: "automationCandidates", stateMutability: "view",
  inputs: [
    { name: "cycle", type: "uint256" },
    { name: "maxScan", type: "uint256" },
    { name: "maxItems", type: "uint256" },
  ],
  outputs: [
    { name: "winnerRequestIds", type: "uint256[]" },
    { name: "failedIds", type: "uint256[]" },
    { name: "refundCandidates", type: "tuple[]", components: [
      { name: "raffleId", type: "uint256" },
      { name: "cursor", type: "uint256" },
    ] },
  ],
}] as const satisfies Abi;

const KIND_HASH: Record<Kind, `0x${string}`> = {
  OPEN_AUCTION: keccak256(stringToHex("OPEN_AUCTION")),
  BLIND_AUCTION: keccak256(stringToHex("BLIND_AUCTION")),
  DUTCH_AUCTION: keccak256(stringToHex("DUTCH_AUCTION")),
  MARKETPLACE: keccak256(stringToHex("MARKETPLACE")),
  RAFFLE: keccak256(stringToHex("RAFFLE")),
};

const encodeCall = encodeFunctionData as unknown as (params: {
  abi: Abi;
  functionName: string;
  args?: readonly unknown[];
}) => `0x${string}`;

const decodeResult = decodeFunctionResult as unknown as (params: {
  abi: Abi;
  functionName: string;
  data: `0x${string}`;
}) => unknown;

function readContract(
  runtime: Runtime<Config>,
  evm: EVM,
  address: Address,
  abi: Abi,
  functionName: string,
  args: readonly unknown[] = [],
): unknown {
  const data = encodeCall({ abi, functionName, args });
  const response = evm.callContract(runtime, {
    call: encodeCallMsg({ from: zeroAddress, to: address, data }),
    blockNumber: LAST_FINALIZED_BLOCK_NUMBER,
  }).result();
  return decodeResult({ abi, functionName, data: bytesToHex(response.data) });
}

function workflow(config: Config) {
  const cron = new cre.capabilities.CronCapability();

  const onCron = (runtime: Runtime<Config>, payload: CronPayload) => {
    if (!payload.scheduledExecutionTime) {
      throw new Error("cron payload missing scheduledExecutionTime");
    }
    const scheduledAt = payload.scheduledExecutionTime.seconds;

    for (const target of runtime.config.evms) {
      const network = getNetwork({
        chainFamily: "evm",
        chainSelectorName: target.chainSelectorName,
        isTestnet: target.isTestnet,
      });
      if (!network) throw new Error(`Unknown EVM network: ${target.chainSelectorName}`);

      const evm = new cre.capabilities.EVMClient(network.chainSelector.selector);
      const registry = target.registryAddress as Address;
      const receiver = target.receiverAddress as Address;
      const chainSelector = BigInt(network.chainSelector.selector);

      const io: AutomationIO = {
        isPaused: () => Boolean(readContract(runtime, evm, receiver, receiverAbi, "paused")),
        instances: (kind, offset, limit) => {
          const [instances, cycle] = readContract(runtime, evm, registry, registryAbi, "automationInstancesWithCycle", [
            KIND_HASH[kind], offset, BigInt(limit),
          ]) as [Address[], bigint];
          return { instances, cycle };
        },
        dueIds: (kind, instance, cycle, maxScan, maxItems) => {
          if (kind === "OPEN_AUCTION") {
            return readContract(runtime, evm, instance, openAbi, "automationDueIds", [cycle, maxScan, maxItems]) as bigint[];
          }
          if (kind === "DUTCH_AUCTION") {
            return readContract(runtime, evm, instance, dutchAbi, "automationDueIds", [cycle, maxScan, maxItems]) as bigint[];
          }
          return readContract(runtime, evm, instance, marketplaceAbi, "automationDueOfferIds", [cycle, maxScan, maxItems]) as bigint[];
        },
        blindReady: (instance) => Boolean(readContract(runtime, evm, instance, blindAbi, "automationReady")),
        raffleCandidates: (instance, cycle, maxScan, maxItems): RaffleCandidates => {
          const [winnerRequestIds, failedIds, refundCandidates] = readContract(runtime, evm, instance, raffleAbi, "automationCandidates", [
            cycle, maxScan, maxItems,
          ]) as [bigint[], bigint[], Array<{ raffleId: bigint; cursor: bigint }>];
          return { winnerRequestIds, failedIds, refundCandidates };
        },
        write: (action) =>
          writeReport(runtime, evm, receiver, encodeReport(action, scheduledAt, chainSelector), target.gasLimit),
        log: (message) => runtime.log(message),
      };

      runAutomation(io, target, scheduledAt);
    }
    return "done";
  };

  return [cre.handler(cron.trigger({ schedule: config.schedule }), onCron)];
}

function writeReport(runtime: Runtime<Config>, evm: EVM, receiver: Address, encodedPayload: `0x${string}`, gasLimit: string): boolean {
  try {
    const report = runtime.report(prepareReportRequest(encodedPayload)).result();
    const writeResult = evm.writeReport(runtime, { receiver, report, gasConfig: { gasLimit } }).result();
    if (writeResult.txStatus !== TxStatus.SUCCESS) {
      runtime.log(`automation write not successful: status=${String(writeResult.txStatus)}`);
      return false;
    }
    return true;
  } catch (error) {
    runtime.log(`automation write failed: ${String(error)}`);
    return false;
  }
}

export async function main() {
  const runner = await Runner.newRunner<Config>({ configSchema });
  await runner.run(workflow);
}

await main();

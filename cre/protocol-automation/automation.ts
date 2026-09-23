

export type Address = `0x${string}`;

export type Kind = "OPEN_AUCTION" | "BLIND_AUCTION" | "DUTCH_AUCTION" | "MARKETPLACE" | "RAFFLE";

export const ACTION = {
  FINALIZE_OPEN_AUCTION: 0,
  FINALIZE_BLIND_AUCTION: 1,
  EXPIRE_DUTCH_AUCTION: 2,
  EXPIRE_OFFER: 3,
  REQUEST_RAFFLE_WINNER: 4,
  PROCESS_RAFFLE_REFUNDS: 5,
  FINALIZE_FAILED_RAFFLE: 6,
} as const;

export const KINDS: readonly Kind[] = ["OPEN_AUCTION", "BLIND_AUCTION", "DUTCH_AUCTION", "MARKETPLACE", "RAFFLE"];

export function kindOrder(scheduledAt: bigint): Kind[] {
  const start = Number((scheduledAt / 60n) % BigInt(KINDS.length));
  return [...KINDS.slice(start), ...KINDS.slice(0, start)];
}

export interface ReportAction {
  action: number;
  instance: Address;
  id: bigint;
  value: bigint;
  cursor: bigint;
}

export interface AutomationLimits {

  instancesPerKindPerRun: number;

  maxIdsPerInstance: number;

  maxScanPerInstance: number;
  maxReportsPerRun: number;

  refundBatchSize: number;

  partitionCount: number;

  partitionIndex: number;
}

export interface RaffleCandidates {
  winnerRequestIds: bigint[];
  failedIds: bigint[];
  refundCandidates: Array<{ raffleId: bigint; cursor: bigint }>;
}

export interface AutomationIO {
  isPaused(): boolean;

  instances(kind: Kind, offset: bigint, limit: number): { instances: Address[]; cycle: bigint };
  dueIds(
    kind: "OPEN_AUCTION" | "DUTCH_AUCTION" | "MARKETPLACE",
    instance: Address,
    cycle: bigint,
    maxScan: bigint,
    maxItems: bigint,
  ): bigint[];
  blindReady(instance: Address): boolean;
  raffleCandidates(instance: Address, cycle: bigint, maxScan: bigint, maxItems: bigint): RaffleCandidates;

  write(action: ReportAction): boolean;
  log(message: string): void;
}

export function discoveryOffset(scheduledAt: bigint, partitionCount: number, partitionIndex: number): bigint {
  if (!Number.isInteger(partitionCount) || partitionCount < 1) throw new Error("partitionCount must be >= 1");
  if (!Number.isInteger(partitionIndex) || partitionIndex < 0 || partitionIndex >= partitionCount) {
    throw new Error("partitionIndex must satisfy 0 <= partitionIndex < partitionCount");
  }
  const slot = scheduledAt / 60n;
  return slot * BigInt(partitionCount) + BigInt(partitionIndex);
}

export function runAutomation(io: AutomationIO, limits: AutomationLimits, scheduledAt: bigint): number {
  if (io.isPaused()) {
    io.log("automation receiver is paused; skipping");
    return 0;
  }

  const offset = discoveryOffset(scheduledAt, limits.partitionCount, limits.partitionIndex);
  const maxItems = BigInt(limits.maxIdsPerInstance);
  const maxScan = BigInt(limits.maxScanPerInstance);
  let writes = 0;

  const submit = (action: ReportAction): boolean => {
    if (writes >= limits.maxReportsPerRun) return false;
    if (io.write(action)) {
      writes++;
      return true;
    }
    return false;
  };
  const full = () => writes >= limits.maxReportsPerRun;

  for (const kind of kindOrder(scheduledAt)) {
    if (full()) break;
    const { instances, cycle } = io.instances(kind, offset, limits.instancesPerKindPerRun);

    for (const instance of instances) {
      if (full()) break;

      if (kind === "OPEN_AUCTION") {
        for (const id of io.dueIds(kind, instance, cycle, maxScan, maxItems)) {
          if (full()) break;
          submit({ action: ACTION.FINALIZE_OPEN_AUCTION, instance, id, value: 0n, cursor: 0n });
        }
      } else if (kind === "BLIND_AUCTION") {
        if (io.blindReady(instance)) {
          submit({ action: ACTION.FINALIZE_BLIND_AUCTION, instance, id: 0n, value: 0n, cursor: 0n });
        }
      } else if (kind === "DUTCH_AUCTION") {
        for (const id of io.dueIds(kind, instance, cycle, maxScan, maxItems)) {
          if (full()) break;
          submit({ action: ACTION.EXPIRE_DUTCH_AUCTION, instance, id, value: 0n, cursor: 0n });
        }
      } else if (kind === "MARKETPLACE") {
        for (const id of io.dueIds(kind, instance, cycle, maxScan, maxItems)) {
          if (full()) break;
          submit({ action: ACTION.EXPIRE_OFFER, instance, id, value: 0n, cursor: 0n });
        }
      } else {
        const { winnerRequestIds, failedIds, refundCandidates } = io.raffleCandidates(instance, cycle, maxScan, maxItems);
        for (const id of winnerRequestIds) {
          if (full()) break;
          submit({ action: ACTION.REQUEST_RAFFLE_WINNER, instance, id, value: 0n, cursor: 0n });
        }
        for (const id of failedIds) {
          if (full()) break;
          submit({ action: ACTION.FINALIZE_FAILED_RAFFLE, instance, id, value: 0n, cursor: 0n });
        }
        for (const candidate of refundCandidates) {
          if (full()) break;
          submit({
            action: ACTION.PROCESS_RAFFLE_REFUNDS,
            instance,
            id: candidate.raffleId,
            value: BigInt(limits.refundBatchSize),
            cursor: candidate.cursor,
          });
        }
      }
    }
  }

  return writes;
}

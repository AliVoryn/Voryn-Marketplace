import { encodeAbiParameters } from "viem";
import type { ReportAction } from "./automation.ts";

export const REPORT_ABI = [
  { type: "uint8" }, { type: "address" }, { type: "uint256" }, { type: "uint256" },
  { type: "uint256" }, { type: "uint64" }, { type: "uint64" },
] as const;

export function encodeReport(action: ReportAction, scheduledAt: bigint, chainSelector: bigint): `0x${string}` {
  return encodeAbiParameters(REPORT_ABI, [
    action.action, action.instance, action.id, action.value, action.cursor, scheduledAt, chainSelector,
  ]);
}

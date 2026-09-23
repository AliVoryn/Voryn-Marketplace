import { z } from "zod";

export const configSchema = z.object({
  schedule: z.string().min(1),
  evms: z.array(z.object({
    chainSelectorName: z.string().min(1),
    isTestnet: z.boolean(),
    registryAddress: z.string().regex(/^0x[0-9a-fA-F]{40}$/),
    receiverAddress: z.string().regex(/^0x[0-9a-fA-F]{40}$/),
    gasLimit: z.string().regex(/^\d+$/),
    instancesPerKindPerRun: z.literal(1),
    maxIdsPerInstance: z.number().int().positive().max(100),

    maxScanPerInstance: z.number().int().positive().max(500),
    maxReportsPerRun: z.number().int().positive().max(50),

    refundBatchSize: z.number().int().positive().max(100),

    partitionCount: z.number().int().positive().max(1000),
    partitionIndex: z.number().int().nonnegative(),
  }).refine((t) => t.partitionIndex < t.partitionCount, {
    message: "partitionIndex must be < partitionCount",
    path: ["partitionIndex"],
  })).length(1),
});

export type Config = z.infer<typeof configSchema>;

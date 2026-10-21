import type { BlockOptionsSchema } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.workflow-sdk-world.options`. */
export type WorkflowSdkWorldSqlOptions = {
  readonly delivery?: string;
  readonly queue?: string;
  readonly batch?: number;
  readonly timeout?: number;
  readonly schedule?: string;
};

export const workflowSdkWorldSqlOptions: BlockOptionsSchema<WorkflowSdkWorldSqlOptions> =
  blockOptions<WorkflowSdkWorldSqlOptions>({
    delivery: option.string({ default: "poll" }),
    queue: option.string(),
    batch: option.number({ default: 20 }),
    timeout: option.number({ default: 30_000 }),
    schedule: option.string({ default: "1 seconds" }),
  });

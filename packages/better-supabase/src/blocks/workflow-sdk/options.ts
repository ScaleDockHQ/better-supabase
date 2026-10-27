import type { BlockOptionsSchema } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks["workflow-sdk"].options`. */
export type WorkflowSdkSqlOptions = {
  readonly delivery?: string;
  readonly queue?: string;
  readonly batch?: number;
  readonly timeout?: number;
  readonly schedule?: string;
  /** Purge ended runs older than this (`30 days`, `12 hours`) every hour. */
  readonly retention?: string;
};

export const workflowSdkSqlOptions: BlockOptionsSchema<WorkflowSdkSqlOptions> =
  blockOptions<WorkflowSdkSqlOptions>({
    delivery: option.string({ default: "poll" }),
    queue: option.string(),
    batch: option.number({ default: 20 }),
    timeout: option.number({ default: 30_000 }),
    schedule: option.string({ default: "1 seconds" }),
    retention: option.string(),
  });

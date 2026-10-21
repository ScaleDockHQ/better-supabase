import type { BlockOptionsSchema } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.work-items.options`. */
export type WorkItemsSqlOptions = {
  readonly prefix?: string;
  readonly maxAssignees?: number;
  readonly extraColumns?: unknown;
};

export const workItemsSqlOptions: BlockOptionsSchema<WorkItemsSqlOptions> =
  blockOptions<WorkItemsSqlOptions>({
    prefix: option.string({ default: "TASK-" }),
    maxAssignees: option.number({ default: 0 }),
    extraColumns: option.unknown(),
  });

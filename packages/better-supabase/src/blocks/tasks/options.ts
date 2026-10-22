import type { BlockOptionsSchema } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.tasks.options`. */
export type TasksSqlOptions = {
  readonly prefix?: string;
  readonly maxAssignees?: number;
  readonly extraColumns?: unknown;
};

export const tasksSqlOptions: BlockOptionsSchema<TasksSqlOptions> =
  blockOptions<TasksSqlOptions>({
    prefix: option.string({ default: "TASK-" }),
    maxAssignees: option.number({ default: 0 }),
    extraColumns: option.unknown(),
  });

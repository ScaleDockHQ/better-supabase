import type { BlockOptionsSchema, ExtraColumns } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.tasks.options`. */
export type TasksSqlOptions = {
  readonly prefix?: string;
  readonly maxAssignees?: number;
  readonly extraColumns?: ExtraColumns;
  /** Whether an item's author can delete it without the delete key. */
  readonly authorCanDelete?: boolean;
  readonly notify?: boolean;
  readonly actionPath?: string;
};

export const tasksSqlOptions: BlockOptionsSchema<TasksSqlOptions> =
  blockOptions<TasksSqlOptions>({
    prefix: option.string({ default: "TASK-" }),
    maxAssignees: option.number({ default: 0 }),
    extraColumns: option.extraColumns(),
    authorCanDelete: option.boolean({ default: true }),
    notify: option.boolean({ default: true }),
    actionPath: option.string(),
  });

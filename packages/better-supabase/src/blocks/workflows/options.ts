import type { BlockOptionsSchema, ExtraColumns } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.workflows.options`. */
export type WorkflowsSqlOptions = {
  /** Extra columns on the runs table. */
  readonly runExtraColumns?: ExtraColumns;
};

export const workflowsSqlOptions: BlockOptionsSchema<WorkflowsSqlOptions> =
  blockOptions<WorkflowsSqlOptions>({ runExtraColumns: option.extraColumns() });

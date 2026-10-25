import type { BlockOptionsSchema, ExtraColumns } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks["workflow-editor"].options`. */
export type WorkflowEditorSqlOptions = { readonly extraColumns?: ExtraColumns };

export const workflowEditorSqlOptions: BlockOptionsSchema<WorkflowEditorSqlOptions> =
  blockOptions<WorkflowEditorSqlOptions>({
    extraColumns: option.extraColumns(),
  });

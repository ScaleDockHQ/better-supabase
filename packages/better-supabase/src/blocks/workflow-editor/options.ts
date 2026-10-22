import type { BlockOptionsSchema } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks["workflow-editor"].options`. */
export type WorkflowEditorSqlOptions = { readonly extraColumns?: unknown };

export const workflowEditorSqlOptions: BlockOptionsSchema<WorkflowEditorSqlOptions> =
  blockOptions<WorkflowEditorSqlOptions>({ extraColumns: option.unknown() });

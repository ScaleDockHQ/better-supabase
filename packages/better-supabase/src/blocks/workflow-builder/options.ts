import { type BlockOptionsSchema, blockOptions, option } from "../options.ts";

/** `blocks.workflow-builder.options`. */
export type WorkflowBuilderSqlOptions = { readonly extraColumns?: unknown };

export const workflowBuilderSqlOptions: BlockOptionsSchema<WorkflowBuilderSqlOptions> =
  blockOptions<WorkflowBuilderSqlOptions>({ extraColumns: option.unknown() });

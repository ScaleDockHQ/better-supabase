import type { BlockOptionsSchema, ExtraColumns } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.approvals.options`. */
export type ApprovalsSqlOptions = {
  readonly policies?: unknown;
  readonly extraColumns?: ExtraColumns;
};

export const approvalsSqlOptions: BlockOptionsSchema<ApprovalsSqlOptions> =
  blockOptions<ApprovalsSqlOptions>({
    policies: option.unknown(),
    extraColumns: option.extraColumns(),
  });

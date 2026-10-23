import type { BlockOptionsSchema } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.approvals.options`. */
export type ApprovalsSqlOptions = {
  readonly policies?: unknown;
  readonly extraColumns?: unknown;
};

export const approvalsSqlOptions: BlockOptionsSchema<ApprovalsSqlOptions> =
  blockOptions<ApprovalsSqlOptions>({
    policies: option.unknown(),
    extraColumns: option.unknown(),
  });

import type { BlockOptionsSchema, ExtraColumns } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.approvals.options`. */
export type ApprovalsSqlOptions = {
  readonly policies?: unknown;
  /**
   * Adds `approval_policies`, where each organization tightens the policies
   * above with its own steps, conditions and mode (ADR 0119).
   */
  readonly tenantPolicies?: boolean;
  readonly extraColumns?: ExtraColumns;
};

export const approvalsSqlOptions: BlockOptionsSchema<ApprovalsSqlOptions> =
  blockOptions<ApprovalsSqlOptions>({
    policies: option.unknown(),
    tenantPolicies: option.boolean({ default: false }),
    extraColumns: option.extraColumns(),
  });

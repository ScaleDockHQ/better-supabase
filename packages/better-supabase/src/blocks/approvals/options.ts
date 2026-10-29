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
  /**
   * Rows of `approval_policies` without an organization are platform policies:
   * platform staff edit them at runtime, they apply to every organization and
   * stand in for a missing config floor. Needs `tenantPolicies`.
   */
  readonly platformPolicies?: boolean;
  /**
   * `"rules"` matches tenant policy conditions through the automations block's
   * rule fields; `"payload"` matches them against the request payload without
   * automations.
   */
  readonly conditions?: "rules" | "payload";
  /** Subject types whose requests may have no organization. */
  readonly tenantless?: readonly string[];
  readonly extraColumns?: ExtraColumns;
  /**
   * `false` sends none of the block's approval notifications, so the app can
   * send its own from the `approval.*` events. Default `true`.
   */
  readonly notifications?: boolean;
  /**
   * Columns the app adds to `approval_policies`, such as a description. Needs
   * `tenantPolicies`; `savePolicy` writes them from `fields`.
   */
  readonly policyExtraColumns?: ExtraColumns;
};

export const approvalsSqlOptions: BlockOptionsSchema<ApprovalsSqlOptions> =
  blockOptions<ApprovalsSqlOptions>({
    policies: option.unknown(),
    tenantPolicies: option.boolean({ default: false }),
    platformPolicies: option.boolean({ default: false }),
    conditions: option.string<"rules" | "payload">({ default: "rules" }),
    tenantless: option.strings(),
    extraColumns: option.extraColumns(),
    notifications: option.boolean({ default: true }),
    policyExtraColumns: option.extraColumns(),
  });

import type { BlockOptionsSchema } from "../options.ts";

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
  /**
   * `false` sends none of the block's approval notifications, so the app can
   * send its own from the `approval.*` events. Default `true`.
   */
  readonly notifications?: boolean;
  /**
   * Per subject type, the columns the app adds to `approval_requests` that
   * `open_approval` fills when a block files a request, as a SQL expression per
   * column over `subject.tenant`, `subject.subject_id`, `subject.action`,
   * `subject.payload` and `subject.requested_by`, such as `{ leave_request: {
   * source: "'hr'", employee_id: "(subject.payload ->> 'employeeId')::uuid" }
   * }`. Each column must be one the app adds to the table.
   */
  readonly requestColumns?: Readonly<
    Record<string, Readonly<Record<string, string>>>
  >;
  /**
   * Columns the app adds to `approval_policies`, such as a description. Needs
   * `tenantPolicies`; `savePolicy` writes them from `fields`.
   */
};

export const approvalsSqlOptions: BlockOptionsSchema<ApprovalsSqlOptions> =
  blockOptions<ApprovalsSqlOptions>({
    policies: option.unknown(),
    tenantPolicies: option.boolean({ default: false }),
    platformPolicies: option.boolean({ default: false }),
    conditions: option.string<"rules" | "payload">({ default: "rules" }),
    tenantless: option.strings(),
    notifications: option.boolean({ default: true }),
    requestColumns:
      option.unknown<
        Readonly<Record<string, Readonly<Record<string, string>>>>
      >(),
  });

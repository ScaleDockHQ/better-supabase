import type { BlockSqlContext } from "../context.ts";

import { filterTreeSql } from "../filter-tree-sql.ts";
import { fail } from "../shared.ts";

/** `blocks.approvals.options.conditions`: who evaluates tenant conditions. */
export type ApprovalConditions = "rules" | "payload";

/**
 * `"rules"` (default) matches conditions through the automations block's rule
 * fields; `"payload"` matches them against the request payload in this module.
 */
export function approvalConditions(ctx: BlockSqlContext): ApprovalConditions {
  const raw = ctx.option("conditions") ?? "rules";

  if (raw !== "rules" && raw !== "payload") {
    throw new TypeError(
      'blocks.approvals.options.conditions must be "rules" or "payload"',
    );
  }

  return raw;
}

/**
 * `approval_condition(node, payload)`: a filter tree matched against a request
 * payload, by path. It visits every node, so a call with an empty payload also
 * checks the tree, and it refuses an unknown node or operator.
 */
export function approvalConditionSql(ctx: BlockSqlContext): string {
  return filterTreeSql({
    fn: ctx.fn("approval_condition"),
    comment:
      "Matches a filter tree (groups of rules with a path, an operator and a value)\nagainst a request payload. A number compares as a number when the payload\nvalue is numeric, anything else as text.",
    invalid: fail(
      "APPROVAL_CONDITIONS_INVALID",
      "conditions must be a filter tree of groups and rules with a path and a known operator",
      "22023",
    ),
  });
}

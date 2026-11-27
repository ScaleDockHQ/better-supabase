import type { BlockSqlContext } from "../context.ts";
import type { ApprovalPolicy } from "./approvals-policies.ts";

import {
  assertCountedApprovers,
  policyOf,
  policySnapshot,
} from "./approvals-policies.ts";
import { hasDecider } from "./direct-approver.ts";
import { OPERATIONS } from "./permissions-model.ts";

/** The subject type of an expense the approvals block decides. */
export const EXPENSE_SUBJECT = "expense";

/**
 * Whether each standalone expense goes through the approvals block:
 * `options.standaloneApprovals`, which needs `tables.reports: null`.
 */
export function standaloneApprovals(ctx: BlockSqlContext): boolean {
  const on = ctx.flag("standaloneApprovals", false);

  if (on && !expensesStandalone(ctx)) {
    throw new TypeError(
      "blocks.expenses.options.standaloneApprovals needs tables.reports: null; reports go through approvals already",
    );
  }

  if (!on && ctx.flag("selfDecideWhenTopOfChain", false)) {
    throw new TypeError(
      "blocks.expenses.options.selfDecideWhenTopOfChain needs standaloneApprovals; decideExpense already lets the owner decide when nobody else can",
    );
  }

  return on;
}

/**
 * `options.policy`, or one step for holders of the approve permission and, with
 * `options.decider`, whoever the app's decider accepts.
 */
export function standalonePolicy(ctx: BlockSqlContext): string {
  const policy = standalonePolicyOf(ctx);

  if (ctx.flag("selfDecideWhenTopOfChain", false)) {
    assertCountedApprovers(
      policy,
      ctx.permissionKey("approve", OPERATIONS["expenses.approve"]),
      "blocks.expenses.options.selfDecideWhenTopOfChain",
    );
  }

  return policySnapshot(policy);
}

function standalonePolicyOf(ctx: BlockSqlContext): ApprovalPolicy {
  const policy = policyOf(
    EXPENSE_SUBJECT,
    "approve",
    ctx.option("policy") ?? {
      steps: [
        {
          approvers: {
            permission: ctx.permissionKey(
              "approve",
              OPERATIONS["expenses.approve"],
            ),
            ...(hasDecider(ctx) ? { decider: true } : {}),
          },
        },
      ],
    },
    "blocks.expenses.options.policy",
  );

  if (policy.run !== undefined) {
    throw new TypeError(
      "blocks.expenses.options.policy.run is not allowed; the final approval approves the expense",
    );
  }

  return policy;
}

export function expensesStandalone(ctx: BlockSqlContext): boolean {
  const reports = ctx.config.tables["reports"] === null;

  if (reports !== (ctx.config.tables["lines"] === null)) {
    throw new TypeError(
      "blocks.expenses.tables.reports and lines map to null together: without reports, each expense is one row of tables.expenses",
    );
  }

  return reports;
}

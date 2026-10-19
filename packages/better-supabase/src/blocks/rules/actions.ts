import type { AsyncResult } from "../../core/result.ts";
import type { ApprovalRequestInput } from "../approvals/approvals.ts";
import type { RuleActionHandler } from "./rules.ts";

import { dbError } from "../../core/errors.ts";
import { err } from "../../core/result.ts";

/** The context `dispatch` passes when rules start approvals or other subject work. */
export interface RuleSubjectContext {
  readonly organizationId: string;
  readonly subjectType: string;
  readonly subjectId: string;
  /** Passed on to the approval request, such as the expense amount. */
  readonly payload?: Readonly<Record<string, unknown>>;
}

/** The part of the approvals client the handler calls. */
export interface RuleApprovals {
  request(input: ApprovalRequestInput): AsyncResult<unknown>;
}

/**
 * The `approvals.request` handler: starts an approval of the subject for the
 * action in the rule's `config.action`, such as `{ kind: "approvals.request",
 * config: { action: "manager_review" } }`.
 */
export function approvalsAction(
  approvals: RuleApprovals,
): RuleActionHandler<RuleSubjectContext> {
  return ({ action, rule, context }) => {
    const name = action.config?.["action"];

    if (typeof name !== "string" || name === "") {
      return err(
        dbError(
          "invalid_request",
          `The rule "${rule.name}" has an approvals.request action without config.action`,
          { hint: "RULE_ACTION_INVALID" },
        ),
      );
    }

    const reason = action.config?.["reason"];

    return approvals.request({
      organizationId: context.organizationId,
      subjectType: context.subjectType,
      subjectId: context.subjectId,
      action: name,
      reason: typeof reason === "string" ? reason : `Rule: ${rule.name}`,
      ...(context.payload === undefined ? {} : { payload: context.payload }),
    });
  };
}

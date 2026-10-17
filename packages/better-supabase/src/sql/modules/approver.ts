import type { ModuleContext } from "../context.ts";
import type { ModuleLayout } from "../module-types.ts";

import { fillTemplate } from "../../core/access-sql.ts";
import { sqlString } from "../../core/template.ts";
import { accessModel } from "./access-model.ts";

/** The `{kind}` of an AI tool call that waits for approval. */
export const AI_TOOL_APPROVAL = "ai-tool";

/** The `{kind}` of a support session request. */
export const SUPPORT_SESSION_APPROVAL = "support-session";

/** A request whose approver the provider decides, as SQL expressions. */
export interface ApprovalRequestSql {
  /**
   * A text literal such as `AI_TOOL_APPROVAL`, quoted by `approverCheck`, or
   * `{ sql }` for a text expression (the approvals block's
   * `<subject type>.<action>`).
   */
  readonly kind: string | { readonly sql: string };
  /** A text expression. */
  readonly subject: string;
  /** An expression of the tenant id type, or `null`. */
  readonly tenant: string;
  /** A uuid expression: the user who asked for the approval. */
  readonly requester: string;
}

/** The provider's eligibility check for one request. */
export interface ApproverCheck {
  /** A boolean SQL expression about the caller. */
  readonly sql: string;
  /** The template it came from, for comments. */
  readonly template: "isApprover" | "canApprove";
  /** Whether the requester is refused before the check runs. */
  readonly distinct: boolean;
}

/**
 * The `authorization.functions.isApprover` check for `request`, when the
 * `provider` access model decides and the provider sets it. Tool calls fall
 * back to the deprecated `canApprove`, where `{tool}` is the subject and
 * `approvals.distinctApprover` decides whether the requester is refused;
 * `isApprover` always refuses the requester. `undefined` leaves the module
 * on its built-in approver.
 */
export function approverCheck(
  ctx: ModuleContext,
  layout: ModuleLayout,
  request: ApprovalRequestSql,
): ApproverCheck | undefined {
  const provider = layout.accessProvider;

  if (provider === undefined || accessModel(ctx) !== "provider") {
    return undefined;
  }

  const { isApprover } = provider.functions;

  if (isApprover !== undefined) {
    return {
      sql: fillTemplate("authorization.functions.isApprover", isApprover, {
        kind:
          typeof request.kind === "string"
            ? sqlString(request.kind)
            : request.kind.sql,
        subject: request.subject,
        tenant: request.tenant,
        requester: request.requester,
        scope: provider.scope,
      }),
      template: "isApprover",
      distinct: true,
    };
  }

  if (request.kind !== AI_TOOL_APPROVAL) {
    return undefined;
  }

  // oxlint-disable-next-line typescript/no-deprecated -- read until every provider sets isApprover.
  const canApprove = provider.functions.canApprove;

  if (canApprove === undefined) {
    return undefined;
  }

  return {
    sql: fillTemplate("authorization.functions.canApprove", canApprove, {
      scope: provider.scope,
      tenant: request.tenant,
      tool: request.subject,
    }),
    template: "canApprove",
    distinct: provider.approvals?.distinctApprover === true,
  };
}

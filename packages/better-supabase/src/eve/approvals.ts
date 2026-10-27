import type {
  ApprovalRequest,
  Approvals,
} from "../blocks/approvals/approvals.ts";
import type {
  BlockTransport,
  DbTransportSource,
} from "../core/block-transport.ts";
import type { RequestContext } from "../core/plugin.ts";
import type { EveContextOptions, EveContextRunner } from "./tools.ts";
import type {
  EveApprovalConfiguration,
  EveApprovalResponseDecision,
  EveApprovalStatus,
  EveSessionAuth,
} from "./types.ts";

import { createApprovals } from "../blocks/approvals/approvals.ts";
import { dbTransport } from "../core/block-transport.ts";
import { eveContext } from "./tools.ts";

/** The approvals methods `approvalPolicy` calls. */
export type EveApprovalsClient = Pick<
  Approvals,
  "request" | "approve" | "reject" | "cancel" | "list"
>;

/** Options for `approvalPolicy`. */
export interface ApprovalPolicyOptions<
  D extends DbTransportSource,
> extends EveContextOptions {
  /** Runs the requester and each responder through `forContext`. */
  readonly server: EveContextRunner<D>;
  /**
   * The approvals client for one user's transport and tenant. Default:
   * `createApprovals({ transport, tenant, schema })`.
   */
  readonly approvals?: (
    transport: BlockTransport,
    tenant: string,
  ) => EveApprovalsClient;
  /** The approvals module schema, for the default client. */
  readonly schema?: string;
  /**
   * The `options.policies` action the request files under. Default: the tool
   * name, so `policies.eve_tool_call.<tool>` sets who approves each tool.
   */
  readonly action?: string | ((toolName: string) => string);
  /** The request's subject type. Default: `eve_tool_call`. */
  readonly subjectType?: string;
  /** The prompt eve shows for the call. */
  readonly prompt?: EveApprovalConfiguration["prompt"];
}

/** The keys the agent needs to file and find its own requests. */
const APPROVAL_SCOPES = ["approvals.read", "approvals.request"];

const FINAL_REJECTIONS: ReadonlySet<ApprovalRequest["status"]> = new Set([
  "rejected",
  "cancelled",
  "expired",
]);

const isUser = (auth: EveSessionAuth | null, authenticator: string): boolean =>
  auth?.principalType === "user" &&
  auth.authenticator === authenticator &&
  auth.principalId !== "";

const tenantOf = (auth: EveSessionAuth | null): string | undefined => {
  const tenant = auth?.attributes["tenantId"];

  return typeof tenant === "string" && tenant !== "" ? tenant : undefined;
};

const statusOf = (request: ApprovalRequest): EveApprovalStatus =>
  request.status === "approved"
    ? { type: "approved", reason: "Approved in the approvals block." }
    : FINAL_REJECTIONS.has(request.status)
      ? {
          type: "denied",
          reason: `The approval request was ${request.status}.`,
        }
      : "user-approval";

const rejected = (reason: string): EveApprovalResponseDecision => ({
  status: "rejected",
  reason,
});

/**
 * An eve tool `approval` backed by the approvals block. `request` files one
 * request per call, as the session's user with the agent's `act` claim and the
 * `approvals.read` and `approvals.request` scopes: the subject is `{ type:
 * "eve_tool_call", id: callId }`, so a replay finds the request it filed
 * instead of opening another. A request that is already approved or rejected
 * settles the call without asking.
 *
 * `response` approves or rejects as the person who answered, through
 * `forContext`, so the block's `canDecide` and `approverOf` decide who may
 * settle the call; the requester can always withdraw it. It allows the answer
 * only once the request reaches a final status that matches it, so a multi-step
 * policy keeps eve's prompt open for the next approver.
 */
export function approvalPolicy<D extends DbTransportSource>(
  options: ApprovalPolicyOptions<D>,
): EveApprovalConfiguration {
  const authenticator = options.authenticator ?? "supabase";
  const subjectType = options.subjectType ?? "eve_tool_call";

  const client =
    options.approvals ??
    ((transport: BlockTransport, tenant: string) =>
      createApprovals({
        transport,
        tenant,
        ...(options.schema === undefined ? {} : { schema: options.schema }),
      }));

  const actionOf = (toolName: string): string =>
    typeof options.action === "function"
      ? options.action(toolName)
      : (options.action ?? toolName);

  const filed = (approvals: EveApprovalsClient, callId: string) =>
    approvals
      .list({ subject: { type: subjectType, id: callId }, status: null })
      .map((requests) => requests[0]);

  return {
    ...(options.prompt === undefined ? {} : { prompt: options.prompt }),
    async request(ctx) {
      const context = eveContext(ctx.session.auth.current, {
        ...options,
        scopes: [...(options.scopes ?? []), ...APPROVAL_SCOPES],
      });

      if (context.tenant === undefined) {
        return {
          type: "denied",
          reason: "The session has no organization to file the approval in.",
        };
      }

      const db = await options.server
        .forContext(context, { reason: "eve" })
        .orThrow();

      const approvals = client(dbTransport(db), context.tenant);
      const existing = await filed(approvals, ctx.callId).orThrow();

      const request =
        existing ??
        (await approvals
          .request(
            { type: subjectType, id: ctx.callId },
            {
              action: actionOf(ctx.toolName),
              reason: `${options.agent} wants to run ${ctx.toolName}`,
              payload: {
                tool: ctx.toolName,
                input: ctx.toolInput ?? null,
                session: ctx.session.id,
              },
            },
          )
          .orThrow());

      return statusOf(request);
    },
    async response({ request, response }) {
      const responder = response.principal;

      if (!isUser(responder, authenticator)) {
        return rejected("Only a signed-in member can answer this approval.");
      }

      const tenant = tenantOf(request.principal) ?? tenantOf(responder);

      if (tenant === undefined) {
        return rejected("The approval has no organization.");
      }

      const context: RequestContext = {
        actor: { id: responder.principalId, kind: "user" },
        tenant,
        claims: { sub: responder.principalId, tenant_id: tenant },
      };

      const db = await options.server.forContext(context, { reason: "eve" });

      if (!db.ok) {
        return rejected(db.error.message);
      }

      const approvals = client(dbTransport(db.data), tenant);
      const existing = await filed(approvals, request.callId);

      if (!existing.ok) {
        return rejected(existing.error.message);
      }

      if (existing.data === undefined) {
        return rejected("No approval request is on file for this call.");
      }

      let current = existing.data;

      if (current.status === "pending") {
        const decided = await (response.decision === "approve"
          ? approvals.approve(current.id)
          : current.requestedBy === responder.principalId
            ? approvals.cancel(current.id)
            : approvals.reject(current.id));

        if (!decided.ok) {
          return rejected(decided.error.message);
        }

        current = decided.data;
      }

      if (current.status === "pending") {
        return rejected(
          "Recorded. The approval needs more approvers before the call can run.",
        );
      }

      const settles =
        response.decision === "approve"
          ? current.status === "approved"
          : current.status !== "approved";

      return settles
        ? { status: "allowed" }
        : rejected(`The approval request is already ${current.status}.`);
    },
  };
}

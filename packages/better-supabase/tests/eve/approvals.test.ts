import { describe, expect, it, vi } from "vitest";

import type { ApprovalRequest } from "../../src/blocks/approvals/approvals.ts";
import type { DbTransportSource } from "../../src/core/block-transport.ts";
import type { RequestContext } from "../../src/core/plugin.ts";
import type {
  EveApprovalContext,
  EveApprovalResponseContext,
  EveApprovalsClient,
  EveSessionAuth,
} from "../../src/eve/index.ts";

import { dbError } from "../../src/core/errors.ts";
import { AsyncResult, err } from "../../src/core/result.ts";
import { approvalPolicy } from "../../src/eve/index.ts";

const REQUESTER = "11111111-1111-4111-8111-111111111111";
const LEAD = "33333333-3333-4333-8333-333333333333";
const OWNER = "44444444-4444-4444-8444-444444444444";
const ORG = "22222222-2222-4222-8222-222222222222";

const member = (id: string): EveSessionAuth => ({
  authenticator: "supabase",
  principalType: "user",
  principalId: id,
  attributes: { tenantId: ORG },
});

const db: DbTransportSource = {
  $executor: {
    name: "fake",
    execute: () => Promise.resolve(err(dbError("not_found", "not used"))),
  },
};

/**
 * An in-memory approvals block: `steps` approvals settle a request, and the
 * user `forContext` ran as is the caller, as with the real block.
 */
function fakeApprovals(steps: number) {
  const requests: ApprovalRequest[] = [];
  let caller = "";

  const update = (id: string, change: Partial<ApprovalRequest>) => {
    const index = requests.findIndex((request) => request.id === id);
    const current = requests[index];

    if (current === undefined) {
      return AsyncResult.err(dbError("not_found", "no request"));
    }

    const next = { ...current, ...change };
    requests[index] = next;

    return AsyncResult.ok(next);
  };

  const client: EveApprovalsClient = {
    request: vi.fn((subject, input) => {
      const request: ApprovalRequest = {
        id: `req_${String(requests.length + 1)}`,
        organizationId: ORG,
        subject,
        action: input.action,
        status: "pending",
        mode: "authorize",
        step: 0,
        steps: [],
        requestedBy: caller,
        payload: input.payload ?? {},
        createdAt: Temporal.Instant.fromEpochMilliseconds(0),
      };

      requests.push(request);

      return AsyncResult.ok(request);
    }),
    list: vi.fn((options = {}) =>
      AsyncResult.ok(
        requests.filter(
          (request) =>
            request.subject.type === options.subject?.type &&
            request.subject.id === options.subject.id,
        ),
      ),
    ),
    approve: vi.fn((id: string) => {
      if (caller === requests.find((r) => r.id === id)?.requestedBy) {
        return AsyncResult.err(dbError("forbidden", "not an approver"));
      }

      const step = (requests.find((r) => r.id === id)?.step ?? 0) + 1;

      return update(
        id,
        step >= steps ? { step, status: "approved" } : { step },
      );
    }),
    reject: vi.fn((id: string) => update(id, { status: "rejected" })),
    cancel: vi.fn((id: string) => update(id, { status: "cancelled" })),
  };

  const contexts: RequestContext[] = [];

  const server = {
    forContext: vi.fn((context: RequestContext) => {
      contexts.push(context);
      caller = context.actor?.id ?? "";

      return AsyncResult.ok(db);
    }),
  };

  const settle = (status: ApprovalRequest["status"]) => {
    const first = requests[0];

    if (first === undefined) {
      throw new TypeError("no request filed");
    }

    requests[0] = { ...first, status };
  };

  return { client, server, requests, contexts, settle };
}

const requestCtx = (callId = "call_1"): EveApprovalContext => ({
  session: {
    id: "sess_1",
    auth: { current: member(REQUESTER), initiator: member(REQUESTER) },
  },
  callId,
  toolName: "create_task",
  toolInput: { title: "Ship it" },
});

const responseCtx = (
  responder: EveSessionAuth,
  decision: "approve" | "cancel",
): EveApprovalResponseContext => ({
  request: {
    callId: "call_1",
    requestId: "input_1",
    principal: member(REQUESTER),
    toolName: "create_task",
  },
  response: { decision, principal: responder },
  session: { id: "sess_1" },
});

const setup = (steps = 1) => {
  const fake = fakeApprovals(steps);

  const policy = approvalPolicy({
    server: fake.server,
    agent: "planner",
    approvals: () => fake.client,
  });

  const respond = policy.response;

  if (respond === undefined) {
    throw new TypeError("approvalPolicy returns a response policy");
  }

  return { ...fake, policy, respond };
};

describe("approvalPolicy", () => {
  it("files one request per call, as the user with the agent claim", async () => {
    const { policy, client, requests, contexts } = setup();

    await expect(policy.request(requestCtx())).resolves.toBe("user-approval");
    await expect(policy.request(requestCtx())).resolves.toBe("user-approval");

    expect(client.request).toHaveBeenCalledOnce();
    expect(requests).toEqual([
      expect.objectContaining({
        subject: { type: "eve_tool_call", id: "call_1" },
        action: "create_task",
        payload: {
          tool: "create_task",
          input: { title: "Ship it" },
          session: "sess_1",
        },
      }),
    ]);
    expect(contexts[0]?.claims).toMatchObject({
      sub: REQUESTER,
      scope: ["approvals.read", "approvals.request"],
      act: { kind: "agent", sub: "planner" },
    });
  });

  it("settles a replayed call from the request's final status", async () => {
    const { policy, settle } = setup();

    await policy.request(requestCtx());
    settle("approved");
    await expect(policy.request(requestCtx())).resolves.toMatchObject({
      type: "approved",
    });

    settle("expired");
    await expect(policy.request(requestCtx())).resolves.toMatchObject({
      type: "denied",
    });
  });

  it("allows an approval once the last step approves", async () => {
    const { policy, respond, contexts } = setup(1);

    await policy.request(requestCtx());
    await expect(
      respond(responseCtx(member(LEAD), "approve")),
    ).resolves.toEqual({ status: "allowed" });
    expect(contexts.at(-1)).toEqual({
      actor: { id: LEAD, kind: "user" },
      tenant: ORG,
      claims: { sub: LEAD, tenant_id: ORG },
    });
  });

  it("keeps the prompt open while a multi-step policy needs more approvers", async () => {
    const { policy, respond, requests } = setup(2);

    await policy.request(requestCtx());
    await expect(
      respond(responseCtx(member(LEAD), "approve")),
    ).resolves.toMatchObject({ status: "rejected" });
    expect(requests[0]?.status).toBe("pending");

    await expect(
      respond(responseCtx(member(OWNER), "approve")),
    ).resolves.toEqual({ status: "allowed" });
    expect(requests[0]?.status).toBe("approved");
  });

  it("rejects an answer the block refuses, and the requester's own approval", async () => {
    const { policy, respond } = setup();

    await policy.request(requestCtx());
    await expect(
      respond(responseCtx(member(REQUESTER), "approve")),
    ).resolves.toEqual({ status: "rejected", reason: "not an approver" });
  });

  it("cancels as the requester and rejects as an approver", async () => {
    const first = setup();

    await first.policy.request(requestCtx());
    await expect(
      first.respond(responseCtx(member(REQUESTER), "cancel")),
    ).resolves.toEqual({ status: "allowed" });
    expect(first.client.cancel).toHaveBeenCalledWith("req_1");

    const second = setup();

    await second.policy.request(requestCtx());
    await expect(
      second.respond(responseCtx(member(LEAD), "cancel")),
    ).resolves.toEqual({ status: "allowed" });
    expect(second.client.reject).toHaveBeenCalledWith("req_1");
    expect(second.requests[0]?.status).toBe("rejected");
  });

  it("does not let an approval through a request that is already rejected", async () => {
    const { policy, respond, settle, client } = setup();

    await policy.request(requestCtx());
    settle("rejected");

    await expect(
      respond(responseCtx(member(LEAD), "approve")),
    ).resolves.toMatchObject({ status: "rejected" });
    expect(client.approve).not.toHaveBeenCalled();
  });

  it("rejects a responder that is not a Supabase user, or a call with no request", async () => {
    const { respond } = setup();

    await expect(
      respond(
        responseCtx({ ...member(LEAD), principalType: "contact" }, "approve"),
      ),
    ).resolves.toMatchObject({ status: "rejected" });
    await expect(
      respond(responseCtx(member(LEAD), "approve")),
    ).resolves.toEqual({
      status: "rejected",
      reason: "No approval request is on file for this call.",
    });
  });
});

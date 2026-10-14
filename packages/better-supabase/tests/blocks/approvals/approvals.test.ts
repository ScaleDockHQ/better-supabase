import { describe, expect, it } from "vitest";

import { createApprovals } from "../../../src/blocks/approvals/index.ts";

function transport(results: Record<string, (args: unknown) => unknown>) {
  const calls: [string, unknown][] = [];
  return {
    calls,
    call(schema: string, fn: string, args: unknown) {
      expect(schema).toBe("app");
      calls.push([fn, args]);
      const result = results[fn];
      if (!result) return Promise.reject(new Error(`unexpected ${fn}`));
      return Promise.resolve(result(args));
    },
  };
}

const REQUEST = {
  id: "r1",
  organizationId: "o",
  subjectType: "invoice",
  subjectId: "i1",
  action: "send",
  status: "pending",
  step: 0,
  steps: [
    { approvers: { permission: "invoices.approve" }, required: 2 },
    { approvers: { users: ["u2"] }, required: 1 },
  ],
  requestedBy: "u1",
  reason: "Q3 invoice",
  payload: { total: 100 },
  expiresAt: "2026-10-08T00:00:00Z",
  decidedAt: null,
  createdAt: "2026-10-01T00:00:00Z",
};

describe("approvals client", () => {
  it("requests, decides, delegates and cancels", async () => {
    const fake = transport({
      request_approval: () => REQUEST,
      decide_approval: (args) => ({
        ...REQUEST,
        status:
          (args as { decision: string }).decision === "rejected"
            ? "rejected"
            : "approved",
        decidedAt: "2026-10-02T00:00:00Z",
      }),
      delegate_approval: () => REQUEST,
      cancel_approval: () => ({ ...REQUEST, status: "cancelled" }),
    });
    const approvals = createApprovals({ transport: fake, schema: "app" });
    const request = await approvals
      .request({
        organizationId: "o",
        subjectType: "invoice",
        subjectId: "i1",
        action: "send",
        reason: "Q3 invoice",
        payload: { total: 100 },
      })
      .orThrow();
    expect(request).toMatchObject({
      id: "r1",
      status: "pending",
      steps: [
        { approvers: { permission: "invoices.approve" }, required: 2 },
        { approvers: { users: ["u2"] }, required: 1 },
      ],
      payload: { total: 100 },
    });
    expect(request.expiresAt?.toString()).toBe("2026-10-08T00:00:00Z");
    expect(request.decidedAt).toBeUndefined();
    const approved = await approvals.approve("r1", "ok").orThrow();
    expect(approved.status).toBe("approved");
    expect(approved.decidedAt?.toString()).toBe("2026-10-02T00:00:00Z");
    expect((await approvals.reject("r1").orThrow()).status).toBe("rejected");
    await approvals.delegate("r1", "u3", "on leave").orThrow();
    expect((await approvals.cancel("r1").orThrow()).status).toBe("cancelled");
    expect(fake.calls).toEqual([
      [
        "request_approval",
        {
          tenant: "o",
          subject_type: "invoice",
          subject_id: "i1",
          action: "send",
          reason: "Q3 invoice",
          payload: { total: 100 },
        },
      ],
      [
        "decide_approval",
        { request_id: "r1", decision: "approved", comment: "ok" },
      ],
      [
        "decide_approval",
        { request_id: "r1", decision: "rejected", comment: null },
      ],
      [
        "delegate_approval",
        { request_id: "r1", to_user: "u3", comment: "on leave" },
      ],
      ["cancel_approval", { request_id: "r1" }],
    ]);
  });

  it("reads a request with its decisions, lists and checks", async () => {
    const fake = transport({
      get_approval: () => ({
        ...REQUEST,
        canDecide: true,
        decisions: [
          {
            id: "d1",
            step: 0,
            approver: "u4",
            decision: "delegated",
            delegateTo: "u5",
            comment: null,
            createdAt: "2026-10-01T01:00:00Z",
          },
        ],
      }),
      list_approvals: () => [REQUEST],
      is_approved: () => true,
    });
    const approvals = createApprovals({ transport: fake, schema: "app" });
    const detail = await approvals.get("r1").orThrow();
    expect(detail.canDecide).toBe(true);
    expect(detail.decisions).toEqual([
      {
        id: "d1",
        step: 0,
        approver: "u4",
        decision: "delegated",
        delegateTo: "u5",
        createdAt: Temporal.Instant.from("2026-10-01T01:00:00Z"),
      },
    ]);
    await approvals.list("o").orThrow();
    await approvals
      .list("o", {
        status: null,
        assigned: true,
        subjectType: "invoice",
        subjectId: "i1",
        pageSize: 10,
        before: Temporal.Instant.from("2026-10-02T00:00:00Z"),
      })
      .orThrow();
    expect(await approvals.isApproved("invoice", "i1", "send").orThrow()).toBe(
      true,
    );
    expect(fake.calls.slice(1, 3)).toEqual([
      [
        "list_approvals",
        {
          tenant: "o",
          status: "pending",
          assigned: false,
          subject_type: null,
          subject_id: null,
          page_size: null,
          before: null,
        },
      ],
      [
        "list_approvals",
        {
          tenant: "o",
          status: null,
          assigned: true,
          subject_type: "invoice",
          subject_id: "i1",
          page_size: 10,
          before: "2026-10-02T00:00:00Z",
        },
      ],
    ]);
  });

  it("refuses a status it doesn't know", async () => {
    const fake = transport({
      cancel_approval: () => ({ ...REQUEST, status: "archived" }),
    });
    const approvals = createApprovals({ transport: fake, schema: "app" });
    expect((await approvals.cancel("r1")).ok).toBe(false);
  });
});

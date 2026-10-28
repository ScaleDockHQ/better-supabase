import { describe, expect, it } from "vitest";

import {
  approvalFingerprint,
  createApprovals,
} from "../../../src/blocks/approvals/index.ts";
import { sha256Hex } from "../../../src/core/block-helpers.ts";

function transport(results: Record<string, (args: unknown) => unknown>) {
  const calls: [string, unknown][] = [];

  return {
    calls,
    call(schema: string, fn: string, args: unknown) {
      expect(schema).toBe("app");
      calls.push([fn, args]);
      const result = results[fn];

      if (!result) {
        return Promise.reject(new Error(`unexpected ${fn}`));
      }

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

const INVOICE = { type: "invoice", id: "i1" };

describe("approvals client", () => {
  it("asks approverOf before deciding, with kind <subject type>.<action>", async () => {
    const fake = transport({
      get_approval: () => ({ ...REQUEST, canDecide: true, decisions: [] }),
      decide_approval: () => ({ ...REQUEST, status: "approved" }),
      delegate_approval: () => REQUEST,
    });

    const seen: unknown[] = [];
    let allow = false;

    const approvals = createApprovals({
      transport: fake,
      schema: "app",
      approver: { userId: "u2", claims: { sub: "u2" } },
      authorization: {
        approverOf: (approver, request) => {
          seen.push([approver.userId, request]);

          return allow;
        },
      },
    });

    const refused = await approvals.approve("r1");
    expect(!refused.ok && refused.error.hint).toBe("APPROVAL_FORBIDDEN");
    expect(seen[0]).toEqual([
      "u2",
      { kind: "invoice.send", subject: "i1", tenant: "o", requester: "u1" },
    ]);
    expect(fake.calls.map(([fn]) => fn)).toEqual(["get_approval"]);
    allow = true;
    expect((await approvals.approve("r1").orThrow()).status).toBe("approved");
    await approvals.delegate("r1", "u3").orThrow();
    expect(fake.calls.map(([fn]) => fn)).toEqual([
      "get_approval",
      "get_approval",
      "decide_approval",
      "get_approval",
      "delegate_approval",
    ]);
  });

  it("refuses without asking when SQL says the caller can't decide", async () => {
    const fake = transport({
      get_approval: () => ({ ...REQUEST, canDecide: false, decisions: [] }),
    });

    let asked = false;

    const approvals = createApprovals({
      transport: fake,
      schema: "app",
      approver: { userId: "u2", claims: {} },
      authorization: {
        approverOf: () => {
          asked = true;

          return true;
        },
      },
    });

    const result = await approvals.reject("r1");
    expect(!result.ok && result.error.kind).toBe("forbidden");
    expect(asked).toBe(false);
    expect(() =>
      createApprovals({
        transport: fake,
        authorization: { approverOf: () => true },
      }),
    ).toThrow(/approver/);
  });

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

    const approvals = createApprovals({
      transport: fake,
      schema: "app",
      tenant: "o",
    });

    const request = await approvals
      .request(INVOICE, {
        action: "send",
        reason: "Q3 invoice",
        payload: { total: 100 },
      })
      .orThrow();

    expect(request).toMatchObject({
      id: "r1",
      subject: INVOICE,
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

    const approvals = createApprovals({
      transport: fake,
      schema: "app",
      tenant: () => "o",
    });

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
    await approvals.list().orThrow();
    await approvals
      .list({
        status: null,
        assigned: true,
        subject: INVOICE,
        pageSize: 10,
        before: Temporal.Instant.from("2026-10-02T00:00:00Z"),
      })
      .orThrow();
    expect(await approvals.isApproved(INVOICE, "send").orThrow()).toBe(true);
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

  it("fails without a tenant", async () => {
    const fake = transport({ is_approved: () => false });
    const approvals = createApprovals({ transport: fake, schema: "app" });

    expect(await approvals.request(INVOICE, { action: "send" })).toMatchObject({
      ok: false,
      error: { kind: "invalid_request", hint: "TENANT_REQUIRED" },
    });
    expect((await approvals.list()).ok).toBe(false);
    expect(fake.calls).toHaveLength(0);
    expect(await approvals.isApproved(INVOICE, "send").orThrow()).toBe(false);
  });

  it("checks requirements, consumes once and manages tenant policies", async () => {
    const conditions = {
      id: "root",
      type: "group",
      combinator: "and",
      rules: [
        {
          id: "c1",
          type: "rule",
          path: ["amount"],
          operator: "gt",
          value: 1000,
        },
      ],
    };

    const POLICY = {
      id: "p1",
      organizationId: "o",
      subjectType: "invoice",
      action: "send",
      name: "Large invoices",
      conditions,
      mode: "authorize",
      steps: [{ approvers: { manager: true } }],
      selfApproval: false,
      expiresIn: "3 days",
      enabled: true,
      createdAt: "2026-10-01T00:00:00Z",
      updatedAt: "2026-10-02T00:00:00Z",
    };

    let required = true;

    const fake = transport({
      approval_requirement: () =>
        required
          ? {
              mode: "confirm",
              steps: [],
              selfApproval: true,
              expiresIn: "1 day",
              policies: ["p1"],
            }
          : null,
      request_approval: () => ({
        ...REQUEST,
        mode: "confirm",
        fingerprint: "ab",
      }),
      consume_approval: () => ({
        ...REQUEST,
        status: "approved",
        consumedAt: "2026-10-03T00:00:00Z",
      }),
      list_approval_policies: () => [
        POLICY,
        {
          ...POLICY,
          id: "p2",
          conditions: null,
          expiresIn: null,
          updatedAt: null,
        },
      ],
      save_approval_policy: () => POLICY,
      remove_approval_policy: () => true,
    });

    const approvals = createApprovals({
      transport: fake,
      schema: "app",
      tenant: "o",
    });

    expect(
      await approvals.requirement("invoice", "send", { amount: 5 }).orThrow(),
    ).toEqual({
      mode: "confirm",
      steps: [],
      selfApproval: true,
      expiresIn: "1 day",
      policies: ["p1"],
    });
    required = false;
    expect(await approvals.requirement("invoice", "send").orThrow()).toBeNull();

    const fingerprint = await approvalFingerprint({ b: 1, a: [1, undefined] });

    const request = await approvals
      .request(INVOICE, { action: "send", fingerprint })
      .orThrow();

    expect(request).toMatchObject({ mode: "confirm", fingerprint: "ab" });

    const consumed = await approvals.consume("r1", fingerprint).orThrow();
    expect(consumed.consumedAt?.toString()).toBe("2026-10-03T00:00:00Z");
    expect(consumed.mode).toBe("authorize");
    await approvals.consume("r1").orThrow();

    const [first, second] = await approvals.listPolicies().orThrow();
    expect(first).toMatchObject({
      id: "p1",
      conditions,
      steps: [{ approvers: { manager: true }, required: 1 }],
      expiresIn: "3 days",
    });
    expect(first?.updatedAt?.toString()).toBe("2026-10-02T00:00:00Z");
    expect(second?.conditions).toBeUndefined();
    expect(second?.expiresIn).toBeUndefined();
    await approvals
      .listPolicies({ subjectType: "invoice", pageSize: 5 })
      .orThrow();

    const saved = await approvals
      .savePolicy({ subjectType: "invoice", action: "send", name: "Large" })
      .orThrow();

    expect(saved.name).toBe("Large invoices");
    expect(await approvals.removePolicy("p1").orThrow()).toBe(true);

    expect(fake.calls).toEqual([
      [
        "approval_requirement",
        {
          tenant: "o",
          subject_type: "invoice",
          action: "send",
          subject: { amount: 5 },
        },
      ],
      [
        "approval_requirement",
        { tenant: "o", subject_type: "invoice", action: "send", subject: {} },
      ],
      [
        "request_approval",
        {
          tenant: "o",
          subject_type: "invoice",
          subject_id: "i1",
          action: "send",
          reason: null,
          payload: {},
          fingerprint,
        },
      ],
      ["consume_approval", { request_id: "r1", fingerprint }],
      ["consume_approval", { request_id: "r1", fingerprint: null }],
      [
        "list_approval_policies",
        { tenant: "o", subject_type: null, page_size: null },
      ],
      [
        "list_approval_policies",
        { tenant: "o", subject_type: "invoice", page_size: 5 },
      ],
      [
        "save_approval_policy",
        {
          tenant: "o",
          policy: { subjectType: "invoice", action: "send", name: "Large" },
        },
      ],
      ["remove_approval_policy", { policy_id: "p1" }],
    ]);
  });

  it("fingerprints JSON with sorted keys", async () => {
    const one = await approvalFingerprint({
      b: [1, { d: 2, c: null }],
      a: "x",
    });

    const two = await approvalFingerprint({
      a: "x",
      b: [1, { c: null, d: 2 }],
    });

    expect(one).toBe(two);
    expect(one).toMatch(/^[0-9a-f]{64}$/);
    expect(one).toBe(await sha256Hex('{"a":"x","b":[1,{"c":null,"d":2}]}'));
    expect(await approvalFingerprint({ a: undefined })).toBe(
      await sha256Hex("{}"),
    );
    expect(await approvalFingerprint([undefined])).toBe(
      await sha256Hex("[null]"),
    );
    expect(await approvalFingerprint(undefined)).toBe(await sha256Hex("null"));
    expect(await approvalFingerprint({ b: 1, a: 2 })).not.toBe(
      await approvalFingerprint({ b: 2, a: 1 }),
    );
  });

  it("refuses conditions that are not a filter group", async () => {
    const fake = transport({
      list_approval_policies: () => [
        {
          id: "p1",
          organizationId: "o",
          subjectType: "invoice",
          action: "send",
          name: "Bad",
          conditions: { type: "rule" },
          mode: "confirm",
          steps: [],
          selfApproval: false,
          enabled: true,
          createdAt: "2026-10-01T00:00:00Z",
        },
      ],
    });

    const approvals = createApprovals({
      transport: fake,
      schema: "app",
      tenant: "o",
    });

    expect((await approvals.listPolicies()).ok).toBe(false);
  });

  it("refuses a status it doesn't know", async () => {
    const fake = transport({
      cancel_approval: () => ({ ...REQUEST, status: "archived" }),
    });

    const approvals = createApprovals({ transport: fake, schema: "app" });
    expect((await approvals.cancel("r1")).ok).toBe(false);
  });
});

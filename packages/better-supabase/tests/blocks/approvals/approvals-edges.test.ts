import { describe, expect, it, vi } from "vitest";

import {
  approvalFingerprint,
  createApprovals,
} from "../../../src/blocks/approvals/index.ts";
import { sha256Hex } from "../../../src/core/block-helpers.ts";

type Handler = (args: Record<string, unknown>) => unknown;

function isHandler(value: unknown): value is Handler {
  return typeof value === "function";
}

function transport(results: Record<string, unknown>) {
  const calls: [string, Record<string, unknown>][] = [];

  return {
    calls,
    call(_schema: string, fn: string, args: Readonly<Record<string, unknown>>) {
      calls.push([fn, { ...args }]);
      const result = results[fn];

      if (result === undefined) {
        return Promise.reject(new Error(`unexpected ${fn}`));
      }

      return Promise.resolve(isHandler(result) ? result({ ...args }) : result);
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
  steps: [],
  createdAt: "2026-10-01T00:00:00Z",
};

const INVOICE = { type: "invoice", id: "i1" };

/** The message of a rejection or a failed Result. */
async function failure(promise: PromiseLike<unknown>): Promise<string> {
  try {
    const result = await promise;

    if (typeof result === "object" && result !== null && "ok" in result) {
      if (result.ok === false && "error" in result) {
        // SAFETY: a failed Result carries an error with a message.
        return (result.error as { message: string }).message;
      }

      return "ok";
    }

    return "ok";
  } catch (cause) {
    return cause instanceof Error ? cause.message : String(cause);
  }
}

describe("approval rows", () => {
  it("reads every optional field of a request", async () => {
    const fake = transport({
      request_approval: {
        ...REQUEST,
        organizationId: null,
        mode: "confirm",
        requestedBy: "u1",
        reason: "why",
        fingerprint: "fp",
        payload: [1],
        steps: [
          {
            approvers: {
              permission: "p",
              role: "r",
              team: "t",
              users: ["a", "b"],
              manager: true,
            },
            required: "all",
          },
          {
            approvers: { role: "r" },
            all: true,
            escalateAfter: "1 day",
            escalateTo: { team: "lead" },
            escalated: true,
          },
          {
            approvers: {},
            required: 3,
            escalateAfter: "2 days",
            escalateTo: {},
          },
        ],
        expiresAt: "2026-10-08T00:00:00Z",
        decidedAt: "2026-10-02T00:00:00Z",
        consumedAt: "2026-10-03T00:00:00Z",
      },
    });

    const request = await createApprovals({ transport: fake, tenant: "o" })
      .request({ subject: INVOICE, input: { action: "send" } })
      .orThrow();

    expect(request).toMatchObject({
      organizationId: null,
      mode: "confirm",
      requestedBy: "u1",
      reason: "why",
      fingerprint: "fp",
      payload: {},
    });

    expect(request.steps).toEqual([
      {
        approvers: {
          permission: "p",
          role: "r",
          team: "t",
          users: ["a", "b"],
          manager: true,
        },
        required: 0,
        all: true,
      },
      {
        approvers: { role: "r" },
        required: 1,
        all: true,
        escalateAfter: "1 day",
        escalateTo: { team: "lead" },
        escalated: true,
      },
      {
        approvers: {},
        required: 3,
        escalateAfter: "2 days",
        escalateTo: {},
        escalated: false,
      },
    ]);

    expect(request.expiresAt?.toString()).toBe("2026-10-08T00:00:00Z");
    expect(request.decidedAt?.toString()).toBe("2026-10-02T00:00:00Z");
    expect(request.consumedAt?.toString()).toBe("2026-10-03T00:00:00Z");
  });

  it("defaults a request without steps, payload or organization", async () => {
    const fake = transport({
      request_approval: { ...REQUEST, organizationId: undefined, steps: null },
    });

    const request = await createApprovals({ transport: fake, tenant: "o" })
      .request({ subject: INVOICE, input: { action: "send" } })
      .orThrow();

    expect(request).toMatchObject({
      organizationId: null,
      mode: "authorize",
      steps: [],
      payload: {},
    });
    expect(request).not.toHaveProperty("expiresAt");
  });

  it("rejects an unknown status or decision", async () => {
    const approvals = (answer: unknown) =>
      createApprovals({
        transport: transport({ get_approval: answer, cancel_approval: answer }),
      });

    expect(
      await failure(approvals({ ...REQUEST, status: "weird" }).cancel("r1")),
    ).toMatch(/unknown approval status weird/);

    expect(
      await failure(
        approvals({
          ...REQUEST,
          decisions: [
            {
              id: "d",
              step: 0,
              decision: "maybe",
              createdAt: REQUEST.createdAt,
            },
          ],
        }).get("r1"),
      ),
    ).toMatch(/unknown approval decision maybe/);
  });

  it("reads a request with its decisions and who can decide", async () => {
    const fake = transport({
      get_approval: {
        ...REQUEST,
        canDecide: true,
        decisions: [
          {
            id: "d1",
            step: 0,
            approver: "u2",
            decision: "delegated",
            delegateTo: "u3",
            comment: "busy",
            createdAt: REQUEST.createdAt,
          },
          {
            id: "d2",
            step: 0,
            decision: "approved",
            createdAt: REQUEST.createdAt,
          },
        ],
      },
    });

    const detail = await createApprovals({ transport: fake })
      .get("r1")
      .orThrow();

    expect(detail.canDecide).toBe(true);
    expect(detail.decisions[0]).toMatchObject({
      approver: "u2",
      delegateTo: "u3",
      comment: "busy",
    });
    expect(detail.decisions[1]).not.toHaveProperty("approver");

    const bare = transport({ get_approval: REQUEST });
    expect(
      await createApprovals({ transport: bare }).get("r1").orThrow(),
    ).toMatchObject({ canDecide: false, decisions: [] });
  });
});

describe("approval calls", () => {
  it("passes the optional request arguments", async () => {
    const fake = transport({ request_approval: REQUEST });
    const approvals = createApprovals({ transport: fake });

    await approvals
      .request({
        subject: INVOICE,
        input: {
          action: "send",
          reason: "r",
          payload: { total: 1 },
          fingerprint: "fp",
          tenantless: true,
          policy: { steps: [{ approvers: { users: ["u"] } }] },
          requestedBy: "u1",
        },
      })
      .orThrow();

    expect(fake.calls[0]![1]).toMatchObject({
      tenant: null,
      reason: "r",
      payload: { total: 1 },
      fingerprint: "fp",
      policy: { steps: [{ approvers: { users: ["u"] } }] },
      requested_by: "u1",
    });

    await approvals
      .request({
        subject: INVOICE,
        input: { action: "send", tenantless: true },
      })
      .orThrow();

    expect(fake.calls[1]![1]).toMatchObject({ reason: null, payload: {} });
    expect(fake.calls[1]![1]).not.toHaveProperty("fingerprint");
    expect(fake.calls[1]![1]).not.toHaveProperty("requested_by");
  });

  it("decides for a user and delegates with a comment", async () => {
    const fake = transport({
      decide_approval: REQUEST,
      delegate_approval: REQUEST,
      consume_approval: REQUEST,
    });

    const approvals = createApprovals({ transport: fake });

    await approvals
      .approve({ id: "r1", comment: "ok", decidedBy: "u9" })
      .orThrow();
    await approvals.reject({ id: "r1" }).orThrow();
    await approvals
      .delegate({ id: "r1", userId: "u3", comment: "go" })
      .orThrow();
    await approvals.consume({ id: "r1", fingerprint: "fp" }).orThrow();
    await approvals.consume({ id: "r1" }).orThrow();

    expect(fake.calls.map(([, args]) => args)).toEqual([
      {
        request_id: "r1",
        decision: "approved",
        comment: "ok",
        decided_by: "u9",
      },
      { request_id: "r1", decision: "rejected", comment: null },
      { request_id: "r1", to_user: "u3", comment: "go" },
      { request_id: "r1", fingerprint: "fp" },
      { request_id: "r1", fingerprint: null },
    ]);
  });

  it("lists with every filter and the defaults", async () => {
    const fake = transport({ list_approvals: [REQUEST] });
    const approvals = createApprovals({ transport: fake, tenant: "o" });

    const rows = await approvals.list().orThrow();
    expect(rows).toHaveLength(1);

    await approvals
      .list({
        status: null,
        assigned: true,
        subject: INVOICE,
        pageSize: 5,
        before: Temporal.Instant.from("2026-10-01T00:00:00Z"),
      })
      .orThrow();

    await approvals.list({ status: "approved", tenantless: true }).orThrow();

    expect(fake.calls.map(([, args]) => args)).toEqual([
      {
        tenant: "o",
        status: "pending",
        assigned: false,
        subject_type: null,
        subject_id: null,
        page_size: null,
        before: null,
      },
      {
        tenant: "o",
        status: null,
        assigned: true,
        subject_type: "invoice",
        subject_id: "i1",
        page_size: 5,
        before: "2026-10-01T00:00:00Z",
      },
      expect.objectContaining({ tenant: null, status: "approved" }),
    ]);
  });

  it("reads the approval requirement, or null when none applies", async () => {
    const fake = transport({
      approval_requirement: (args: Record<string, unknown>) =>
        args["action"] === "none"
          ? null
          : {
              mode: "confirm",
              steps: undefined,
              selfApproval: true,
              policies: ["p1"],
              expiresIn: "2 days",
              effects: ["money"],
            },
    });

    const approvals = createApprovals({ transport: fake, tenant: "o" });

    expect(
      await approvals
        .requirement({
          subjectType: "invoice",
          action: "send",
          payload: { total: 1 },
        })
        .orThrow(),
    ).toEqual({
      mode: "confirm",
      steps: [],
      selfApproval: true,
      policies: ["p1"],
      expiresIn: "2 days",
      effects: ["money"],
    });
    expect(fake.calls[0]![1]).toMatchObject({ subject: { total: 1 } });

    expect(
      await approvals
        .requirement({
          subjectType: "invoice",
          action: "none",
          tenantless: true,
        })
        .orThrow(),
    ).toBeNull();
    expect(fake.calls[1]![1]).toMatchObject({ tenant: null, subject: {} });
  });

  it("reads a requirement without effects, expiry or policies", async () => {
    const fake = transport({ approval_requirement: { steps: [] } });

    expect(
      await createApprovals({ transport: fake, tenant: "o" })
        .requirement({ subjectType: "invoice", action: "send" })
        .orThrow(),
    ).toEqual({
      mode: "authorize",
      steps: [],
      selfApproval: false,
      policies: [],
    });
  });

  it("lists, saves and removes tenant and platform policies", async () => {
    const policy = {
      id: "p1",
      organizationId: "o",
      subjectType: "*",
      action: "*",
      effect: "money",
      name: "Big",
      mode: "confirm",
      steps: [{ approvers: { role: "r" }, required: 1 }],
      selfApproval: true,
      enabled: false,
      createdAt: "2026-10-01T00:00:00Z",
      updatedAt: "2026-10-02T00:00:00Z",
      expiresIn: "3 days",
      conditions: { type: "group", rules: [] },
      fields: { region: "eu" },
    };

    const fake = transport({
      list_approval_policies: [
        policy,
        { ...policy, id: "p2", conditions: null },
      ],
      save_approval_policy: { ...policy, fields: null },
      remove_approval_policy: true,
    });

    const approvals = createApprovals({ transport: fake, tenant: "o" });

    const listed = await approvals
      .listPolicies({ subjectType: "invoice", pageSize: 10 })
      .orThrow();

    expect(listed[0]).toMatchObject({
      effect: "money",
      enabled: false,
      expiresIn: "3 days",
      conditions: { type: "group" },
      fields: { region: "eu" },
    });
    expect(listed[1]).not.toHaveProperty("conditions");
    expect(fake.calls[0]![1]).toMatchObject({
      subject_type: "invoice",
      page_size: 10,
    });

    const saved = await approvals
      .savePolicy({ input: { name: "Big" }, platform: true })
      .orThrow();

    expect(saved).not.toHaveProperty("fields");
    expect(fake.calls[1]![1]).toMatchObject({ tenant: null });

    await approvals.listPolicies({ platform: true }).orThrow();
    expect(fake.calls[2]![1]).toMatchObject({
      tenant: null,
      subject_type: null,
      page_size: null,
    });

    expect(await approvals.removePolicy("p1").orThrow()).toBe(true);
  });

  it("refuses a stored policy whose conditions are not a filter group", async () => {
    const fake = transport({
      save_approval_policy: {
        id: "p1",
        subjectType: "*",
        action: "*",
        name: "Bad",
        createdAt: "2026-10-01T00:00:00Z",
        conditions: { type: "rule" },
      },
    });

    expect(
      await failure(
        createApprovals({ transport: fake, tenant: "o" }).savePolicy({
          input: { name: "Bad" },
        }),
      ),
    ).toMatch(/approval conditions are/);
  });
});

describe("approver checks", () => {
  const detail = (extra: Record<string, unknown>) => ({
    ...REQUEST,
    canDecide: true,
    decisions: [],
    ...extra,
  });

  it("omits the tenant and requester the request lacks, and refuses when approverOf throws", async () => {
    const approverOf = vi.fn();

    const fake = transport({
      get_approval: detail({ organizationId: null }),
      decide_approval: REQUEST,
    });

    const approvals = createApprovals({
      transport: fake,
      approver: { userId: "u2", claims: {} },
      authorization: { approverOf },
    });

    approverOf.mockReturnValueOnce(true);
    await approvals.approve({ id: "r1" }).orThrow();
    expect(approverOf.mock.calls[0]![1]).toEqual({
      kind: "invoice.send",
      subject: "i1",
    });

    approverOf.mockRejectedValueOnce(new Error("authz down"));
    const result = await approvals.approve({ id: "r1" });
    expect(!result.ok && result.error.hint).toBe("APPROVAL_FORBIDDEN");
  });
});

describe("waiting, guarding and deciding for a subject", () => {
  it("waits until the request leaves pending", async () => {
    let reads = 0;

    const fake = transport({
      request_approval: REQUEST,
      get_approval: () => {
        reads += 1;

        return { ...REQUEST, status: reads < 3 ? "pending" : "approved" };
      },
    });

    const approvals = createApprovals({ transport: fake, tenant: "o" });

    const done = await approvals
      .requestAndWait({
        subject: INVOICE,
        input: { action: "send" },
        intervalMs: 1,
      })
      .orThrow();

    expect(done.status).toBe("approved");
    expect(reads).toBe(3);
  });

  it("times out, stops on abort and passes a failed read through", async () => {
    const pending = transport({
      request_approval: REQUEST,
      get_approval: REQUEST,
    });

    const approvals = createApprovals({ transport: pending, tenant: "o" });

    const timedOut = await approvals.requestAndWait({
      subject: INVOICE,
      input: { action: "send" },
      timeoutMs: 5,
      intervalMs: 50,
    });

    expect(!timedOut.ok && timedOut.error.hint).toBe("APPROVAL_WAIT_TIMEOUT");

    const aborted = await approvals.requestAndWait({
      subject: INVOICE,
      input: { action: "send" },
      signal: AbortSignal.abort(),
    });

    expect(!aborted.ok && aborted.error.hint).toBe("APPROVAL_WAIT_TIMEOUT");

    const broken = transport({
      request_approval: REQUEST,
      get_approval: () => {
        throw new Error("read failed");
      },
    });

    const failed = await createApprovals({
      transport: broken,
      tenant: "o",
    }).requestAndWait({ subject: INVOICE, input: { action: "send" } });

    expect(failed.ok).toBe(false);
  });

  it("decides the pending request for a subject and action", async () => {
    const fake = transport({
      list_approvals: [
        { ...REQUEST, id: "other", action: "void" },
        { ...REQUEST, id: "r1" },
      ],
      decide_approval: (args: Record<string, unknown>) => ({
        ...REQUEST,
        status: args["decision"] === "approved" ? "approved" : "rejected",
      }),
    });

    const approvals = createApprovals({ transport: fake, tenant: "o" });

    const approved = await approvals
      .decideForSubject({
        subject: INVOICE,
        action: "send",
        decision: "approve",
        comment: "fine",
      })
      .orThrow();

    expect(approved.status).toBe("approved");

    const rejected = await approvals
      .decideForSubject({
        subject: INVOICE,
        action: "send",
        decision: "reject",
      })
      .orThrow();

    expect(rejected.status).toBe("rejected");

    const missing = await approvals.decideForSubject({
      subject: INVOICE,
      action: "refund",
      decision: "approve",
    });

    expect(!missing.ok && missing.error.kind).toBe("not_found");
  });

  it("runs a guarded action once approved and files a request otherwise", async () => {
    let approved = true;

    const fake = transport({
      is_approved: () => approved,
      request_approval: REQUEST,
    });

    const logger = { debug() {}, info() {}, warn() {}, error() {} };

    const approvals = createApprovals({ transport: fake, tenant: "o", logger });

    const run = vi.fn(() => 42);

    expect(
      await approvals
        .guarded({ subject: INVOICE, action: "send", run })
        .orThrow(),
    ).toEqual({ ran: true, value: 42 });

    approved = false;

    const filed = await approvals
      .guarded({
        subject: INVOICE,
        action: "send",
        request: { action: "ignored", reason: "because" },
        run,
      })
      .orThrow();

    expect(filed.ran).toBe(false);
    expect(run).toHaveBeenCalledOnce();
    expect(fake.calls.at(-1)![1]).toMatchObject({
      action: "send",
      reason: "because",
    });
  });
});

describe("fingerprints", () => {
  it("sorts keys, drops undefined members and keeps array holes as null", async () => {
    expect(await approvalFingerprint({ b: [1, undefined], a: undefined })).toBe(
      await sha256Hex('{"b":[1,null]}'),
    );
    expect(await approvalFingerprint(undefined)).toBe(await sha256Hex("null"));
    expect(await approvalFingerprint({ b: 1, a: { d: 2, c: 3 } })).toBe(
      await sha256Hex('{"a":{"c":3,"d":2},"b":1}'),
    );
    expect(await approvalFingerprint({ a: 1, b: 2 })).toBe(
      await approvalFingerprint({ b: 2, a: 1 }),
    );
  });
});

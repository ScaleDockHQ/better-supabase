import { beforeEach, describe, expect, it, vi } from "vitest";

import type { OutboxEvent } from "../../src/blocks/outbox/outbox.ts";

const start = vi.fn(
  async (_workflow: unknown, _args: unknown[], _options: unknown) => ({
    runId: "wrun_new",
  }),
);

const getRun = vi.fn((runId: string) => ({ runId }));

const getHookByToken = vi.fn(async (_token: string) => ({
  token: "t",
  runId: "wrun_1",
  metadata: Promise.resolve<unknown>({}),
}));

const listRuns = vi.fn(
  async (_params: unknown): Promise<{ data: { runId: string }[] }> => ({
    data: [],
  }),
);

const world = { analytics: { runs: { list: listRuns } } };

vi.mock("workflow/api", () => ({ start, getRun, getHookByToken }));

vi.mock("workflow/runtime", () => ({ getWorld: async () => world }));

vi.mock("workflow", () => ({ createHook: vi.fn(), sleep: vi.fn() }));

const {
  authorizeHook,
  contextAttributes,
  HookForbiddenError,
  hookMetadata,
  protectWebHandler,
  startFor,
  startOnEvent,
  workflowContext,
  workflowStarter,
} = await import("../../src/workflow-sdk/index.ts");

const user = { actor: { id: "u1", kind: "user" as const }, tenant: "t1" };
const approve = async (_id: string): Promise<void> => undefined;

beforeEach(() => {
  start.mockClear();
  listRuns.mockClear();
  listRuns.mockResolvedValue({ data: [] });
});

function event(overrides: Partial<OutboxEvent> = {}): OutboxEvent {
  return {
    position: 1,
    id: "e1",
    type: "invoice.paid",
    payload: { invoice: "i1" },
    source: null,
    subject: null,
    tenant: "t1",
    key: null,
    actorId: "u1",
    createdAt: Temporal.Instant.from("2026-01-01T00:00:00Z"),
    ...overrides,
  };
}

describe("context", () => {
  it("keeps the actor and tenant and drops the claims", () => {
    expect(workflowContext({ ...user, claims: { secret: true } })).toEqual(
      user,
    );
    expect(contextAttributes(user)).toEqual({
      "bs.tenant": "t1",
      "bs.actor": "u1",
    });
    expect(
      contextAttributes({ actor: { id: "svc", kind: "service" } }),
    ).toEqual({});
    expect(hookMetadata(user, "invoice.approve")).toEqual({
      "bs.tenant": "t1",
      "bs.actor": "u1",
      "bs.permission": "invoice.approve",
    });
    expect(hookMetadata({})).toEqual({});
  });

  it("keeps the delegation claims and the ticket", () => {
    const delegated = {
      ...user,
      claims: { client_id: "mcp", scope: "posts:read", email: "x@y.z" },
    };

    expect(workflowContext(delegated)).toEqual({
      ...user,
      claims: { client_id: "mcp", scope: "posts:read" },
    });
    expect(workflowContext(user, { ticket: "tk-1" })).toEqual({
      ...user,
      ticket: "tk-1",
    });
    expect(contextAttributes({ ...user, ticket: "tk-1" })).toEqual({
      "bs.tenant": "t1",
      "bs.actor": "u1",
      "bs.ticket": "tk-1",
    });
    expect(() =>
      workflowContext({ ...user, claims: { act: { kind: "root", sub: "a" } } }),
    ).toThrow(TypeError);
  });
});

describe("startFor", () => {
  it("starts with the context attributes and the key", async () => {
    const run = await startFor(user, approve, ["i1"], {
      idempotencyKey: "k1",
      attributes: { plan: "pro", "bs.actor": "spoofed" },
    });

    expect(run.runId).toBe("wrun_new");
    expect(listRuns).toHaveBeenCalledWith({
      attributes: { "bs.key": "k1" },
      pagination: { limit: 1 },
    });
    expect(start.mock.calls[0]?.[2]).toEqual({
      attributes: {
        plan: "pro",
        "bs.tenant": "t1",
        "bs.actor": "u1",
        "bs.key": "k1",
      },
    });
  });

  it("drops caller principal attributes and stores the subject", async () => {
    await startFor(user, approve, ["i1"], {
      attributes: { "bs.principal_kind": "system", "bs.principal": "x" },
      subject: { type: "deal", id: "d1" },
    });
    expect(start.mock.calls[0]?.[2]).toEqual({
      attributes: {
        "bs.tenant": "t1",
        "bs.actor": "u1",
        "bs.subject": "deal/d1",
      },
    });
    await expect(
      startFor(user, approve, ["i1"], { subject: { type: "a/b", id: "1" } }),
    ).rejects.toThrow(TypeError);
  });

  it("stores the ticket as bs.ticket", async () => {
    await startFor(user, approve, ["i1"], { ticket: "tk-1" });
    expect(start.mock.calls[0]?.[2]).toEqual({
      attributes: { "bs.tenant": "t1", "bs.actor": "u1", "bs.ticket": "tk-1" },
    });
    await startFor({ ...user, ticket: "from-context" }, approve, ["i1"]);
    expect(start.mock.calls[1]?.[2]).toMatchObject({
      attributes: { "bs.ticket": "from-context" },
    });
    await expect(
      startFor(user, approve, ["i1"], { ticket: "" }),
    ).rejects.toThrow(TypeError);
  });

  it("returns the run that already has the key", async () => {
    listRuns.mockResolvedValueOnce({ data: [{ runId: "wrun_old" }] });
    const run = await startFor(user, approve, ["i1"], { idempotencyKey: "k1" });
    expect(run.runId).toBe("wrun_old");
    expect(start).not.toHaveBeenCalled();
  });

  it("starts without a lookup when there is no key or no analytics", async () => {
    const other = { analytics: undefined } as never;
    await startFor({}, approve, ["i1"], { idempotencyKey: "k", world: other });
    expect(start.mock.calls[0]?.[2]).toEqual({
      attributes: { "bs.key": "k" },
      world: other,
    });
    await startFor({}, approve, ["i1"]);
    expect(listRuns).not.toHaveBeenCalled();
  });
});

const publisher = { publisher: "p1", permissions: ["invoice.approve"] };

const asPublisher = {
  actor: { id: "p1", kind: "user" as const },
  tenant: "t1",
  claims: { bs_permission_cap: ["invoice.approve"] },
};

describe("workflowStarter", () => {
  it("starts a schedule as its runAs publisher, with the creator as the trigger", async () => {
    const starter = workflowStarter(
      { approve },
      {
        runAs: publisher,
        args: (call, context) => [context, ...(call.input as unknown[])],
      },
    );

    expect(
      await starter({
        source: "schedule",
        workflow: "approve",
        input: ["i1"],
        tenant: "t1",
        actor: "u1",
        idempotencyKey: "schedule:s1:x",
      }),
    ).toBe("wrun_new");
    expect(start.mock.calls[0]?.[1]).toEqual([asPublisher, "i1"]);
    expect(start.mock.calls[0]?.[2]).toEqual({
      attributes: {
        "bs.publisher": "p1",
        "bs.trigger": "u1",
        "bs.tenant": "t1",
        "bs.actor": "u1",
        "bs.principal_kind": "user",
        "bs.principal": "p1",
        "bs.key": "schedule:s1:x",
      },
    });
  });

  it("refuses a schedule without runAs, or when runAs returns null", async () => {
    const call = {
      source: "schedule" as const,
      workflow: "approve",
      input: [],
      tenant: "t1",
      actor: "u1",
      idempotencyKey: "schedule:s1:x",
    };

    await expect(workflowStarter({ approve })(call)).rejects.toThrow(
      "needs a runAs publisher",
    );
    await expect(
      workflowStarter({ approve }, { runAs: () => null })(call),
    ).rejects.toThrow("runAs refused");
    await expect(
      workflowStarter(
        { approve },
        { runAs: { publisher: "", permissions: [] } },
      )(call),
    ).rejects.toThrow("needs a publisher");
    expect(start).not.toHaveBeenCalled();
  });

  it("starts an admission request as its actor", async () => {
    const starter = workflowStarter({ approve });
    await starter({
      source: "admission",
      workflow: "approve",
      input: "single",
      tenant: "t1",
      actor: "u1",
      idempotencyKey: "admission:q1",
    });
    expect(start.mock.calls[0]?.[1]).toEqual(["single"]);
    expect(start.mock.calls[0]?.[2]).toMatchObject({
      attributes: { "bs.actor": "u1", "bs.key": "admission:q1" },
    });
    await expect(
      starter({
        source: "admission",
        workflow: "missing",
        input: [],
        tenant: undefined,
        actor: undefined,
        idempotencyKey: "k",
      }),
    ).rejects.toThrow('no workflow named "missing"');
  });
});

describe("authorizeHook", () => {
  it("lets the actor resume their own hook", async () => {
    getHookByToken.mockResolvedValueOnce({
      token: "t",
      runId: "wrun_1",
      metadata: Promise.resolve(hookMetadata(user)),
    });
    expect((await authorizeHook("t", user)).runId).toBe("wrun_1");
  });

  it("lets a member with the permission resume it, and refuses others", async () => {
    const metadata = hookMetadata(
      { actor: { id: "owner", kind: "user" }, tenant: "t1" },
      "invoice.approve",
    );

    const hook = () => ({
      token: "t",
      runId: "wrun_1",
      metadata: Promise.resolve<unknown>(metadata),
    });

    const can = vi.fn(
      async (tenant: string, permission: string) =>
        tenant === "t1" && permission === "invoice.approve",
    );

    getHookByToken.mockResolvedValueOnce(hook());
    await expect(authorizeHook("t", user, { can })).resolves.toBeDefined();
    expect(can).toHaveBeenCalledWith("t1", "invoice.approve");

    getHookByToken.mockResolvedValueOnce(hook());
    await expect(authorizeHook("t", user)).rejects.toBeInstanceOf(
      HookForbiddenError,
    );
    getHookByToken.mockResolvedValueOnce(hook());
    await expect(authorizeHook("t", {}, { can })).rejects.toThrow(
      "may not resume",
    );
    getHookByToken.mockResolvedValueOnce({
      token: "t",
      runId: "wrun_1",
      metadata: Promise.resolve<unknown>("not an object"),
    });

    const error = await authorizeHook("t", user, { can }).catch(
      (cause: unknown) => cause,
    );

    expect(error).toMatchObject({ status: 403, name: "HookForbiddenError" });
  });
});

describe("startOnEvent", () => {
  it("starts matching events once each, as the runAs publisher", async () => {
    const handler = startOnEvent(approve, {
      types: ["invoice.*"],
      runAs: publisher,
    });

    await handler([
      event(),
      event({ id: "e2", type: "customer.created" }),
      event({ id: "e3", actorId: null, tenant: null, type: "invoice.voided" }),
    ]);
    expect(start).toHaveBeenCalledTimes(2);
    expect(start.mock.calls[0]?.[1]).toEqual([{ invoice: "i1" }]);
    expect(start.mock.calls[0]?.[2]).toEqual({
      attributes: {
        "bs.publisher": "p1",
        "bs.trigger": "u1",
        "bs.tenant": "t1",
        "bs.actor": "u1",
        "bs.principal_kind": "user",
        "bs.principal": "p1",
        "bs.key": "event:e1",
      },
    });
    expect(start.mock.calls[1]?.[2]).toEqual({
      attributes: {
        "bs.publisher": "p1",
        "bs.principal_kind": "user",
        "bs.principal": "p1",
        "bs.key": "event:e3",
      },
    });
  });

  it("maps arguments, matches every type with * and skips a refused event", async () => {
    const handler = startOnEvent(approve, {
      types: ["*"],
      args: (entry): [string] => [entry.id],
      runAs: (entry) => (entry.id === "e1" ? publisher : null),
      world: world as never,
    });

    await handler([event({ type: "anything" }), event({ id: "e2" })]);
    expect(start).toHaveBeenCalledOnce();
    expect(start.mock.calls[0]?.[1]).toEqual(["e1"]);

    const exact = startOnEvent(approve, {
      types: ["invoice.paid"],
      runAs: publisher,
    });

    await exact([event({ type: "invoice.paidx" })]);
    expect(start).toHaveBeenCalledOnce();
  });

  it("records a ticket per event and passes the publisher's context to args", async () => {
    const seen: unknown[] = [];

    const handler = startOnEvent(approve, {
      types: ["*"],
      runAs: publisher,
      ticket: (entry) => (entry.id === "e1" ? `ticket:${entry.id}` : undefined),
      args: (entry, context): [string] => {
        seen.push(context);

        return [entry.id];
      },
    });

    await handler([event(), event({ id: "e2" })]);
    expect(seen).toEqual([
      { ...asPublisher, ticket: "ticket:e1" },
      asPublisher,
    ]);
    expect(start.mock.calls[0]?.[2]).toEqual({
      attributes: {
        "bs.publisher": "p1",
        "bs.trigger": "u1",
        "bs.tenant": "t1",
        "bs.actor": "u1",
        "bs.principal_kind": "user",
        "bs.principal": "p1",
        "bs.ticket": "ticket:e1",
        "bs.key": "event:e1",
      },
    });
  });
});

describe("protectWebHandler", () => {
  it("answers 401 without a session and 403 without the permission", async () => {
    const handler = vi.fn(async () => new Response("ok"));
    const answers: (boolean | undefined)[] = [undefined, false, true];

    const protectedHandler = protectWebHandler(handler, "workflow.read", {
      can: (_request, permission) => {
        expect(permission).toBe("workflow.read");

        return answers.shift();
      },
    });

    const request = new Request("https://app.test/_workflow");
    const unauthorized = await protectedHandler(request);
    expect(unauthorized.status).toBe(401);
    expect(unauthorized.headers.get("content-type")).toBe(
      "application/problem+json",
    );
    expect(await unauthorized.json()).toMatchObject({ title: "Unauthorized" });
    expect((await protectedHandler(request)).status).toBe(403);
    expect(await (await protectedHandler(request)).text()).toBe("ok");
    expect(handler).toHaveBeenCalledOnce();
  });
});

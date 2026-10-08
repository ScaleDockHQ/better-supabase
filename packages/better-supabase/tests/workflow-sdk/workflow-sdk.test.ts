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

describe("workflowStarter", () => {
  it("starts the named workflow as the schedule's creator", async () => {
    const starter = workflowStarter({ approve });
    expect(
      await starter({
        workflow: "approve",
        input: ["i1"],
        tenant: "t1",
        actor: "u1",
        idempotencyKey: "schedule:s1:x",
      }),
    ).toBe("wrun_new");
    expect(start.mock.calls[0]?.[1]).toEqual(["i1"]);
    expect(start.mock.calls[0]?.[2]).toMatchObject({
      attributes: { "bs.key": "schedule:s1:x", "bs.actor": "u1" },
    });
    await starter({
      workflow: "approve",
      input: "single",
      tenant: undefined,
      actor: undefined,
      idempotencyKey: "admission:q1",
    });
    expect(start.mock.calls[1]?.[1]).toEqual(["single"]);
    await expect(
      starter({
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
  it("starts matching events once each, as their actor", async () => {
    const handler = startOnEvent(approve, { types: ["invoice.*"] });
    await handler([
      event(),
      event({ id: "e2", type: "customer.created" }),
      event({ id: "e3", actorId: null, tenant: null, type: "invoice.voided" }),
    ]);
    expect(start).toHaveBeenCalledTimes(2);
    expect(start.mock.calls[0]?.[1]).toEqual([{ invoice: "i1" }]);
    expect(start.mock.calls[0]?.[2]).toEqual({
      attributes: { "bs.tenant": "t1", "bs.actor": "u1", "bs.key": "event:e1" },
    });
    expect(start.mock.calls[1]?.[2]).toEqual({
      attributes: { "bs.key": "event:e3" },
    });
  });

  it("maps arguments and matches every type with *", async () => {
    const handler = startOnEvent(approve, {
      types: ["*"],
      args: (entry): [string] => [entry.id],
      world: world as never,
    });
    await handler([event({ type: "anything" })]);
    expect(start.mock.calls[0]?.[1]).toEqual(["e1"]);
    const exact = startOnEvent(approve, { types: ["invoice.paid"] });
    await exact([event({ type: "invoice.paidx" })]);
    expect(start).toHaveBeenCalledOnce();
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

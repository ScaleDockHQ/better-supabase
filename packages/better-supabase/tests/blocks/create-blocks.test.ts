import { describe, expect, expectTypeOf, it, vi } from "vitest";

import type { AiFiles } from "../../src/blocks/ai-files/index.ts";
import type { BlockContext, Notifier } from "../../src/blocks/index.ts";
import type { CloudEvent } from "../../src/events/index.ts";

import { auditBlock } from "../../src/blocks/audit/index.ts";
import {
  BLOCK_EVENT_SOURCE,
  createBlocks,
  defineBlock,
  defineBlocks,
  defineEvents,
  event,
  rpcTransport,
} from "../../src/blocks/index.ts";
import { rateLimitBlock } from "../../src/blocks/jobs/index.ts";
import { metricsBlock } from "../../src/blocks/metrics/index.ts";
import {
  organizationsBlock,
  type OrganizationsEvents,
} from "../../src/blocks/organizations/index.ts";
import { remindersBlock } from "../../src/blocks/reminders/index.ts";
import { searchSink } from "../../src/blocks/search/index.ts";
import { tenantBlock } from "../../src/blocks/tenant/manifest.ts";
import { emitBlockEvent } from "../../src/core/block-events.ts";
import { dbError } from "../../src/core/errors.ts";
import { EventHub } from "../../src/core/events.ts";
import { AsyncResult } from "../../src/core/result.ts";
import { vaultCredentials } from "../../src/credentials/index.ts";

const transport = rpcTransport({
  schema: () => ({ rpc: () => Promise.resolve({ data: null, error: null }) }),
});

const fakeFiles = {} as AiFiles;

const cloudEvent = (type: string, data: unknown): CloudEvent => ({
  specversion: "1.0",
  id: type,
  source: "/test",
  type: `dev.better-supabase.${type}`,
  time: "2026-10-14T10:00:00Z",
  data,
});

/** A notifications stand-in that provides the notifier port. */
const notifier = (send: Notifier["send"]) =>
  defineBlock({
    name: "notifications",
    create: (_options: BlockContext): Notifier => ({ send }),
    provides: { notifier: (client) => client },
    category: "collaboration",
  });

/** A block that records the options it was built with. */
const recorder = <const C extends Record<string, "optional" | "required">>(
  seen: Record<string, unknown>[],
  consumes?: C,
) =>
  defineBlock({
    name: "recorder",
    create: (options: Record<string, unknown>) => {
      seen.push(options);

      return {};
    },
    ...(consumes === undefined ? {} : { consumes }),
    category: "work",
  });

describe("createBlocks sinks", () => {
  it("has none without a block that provides one", () => {
    const blocks = createBlocks({ transport }, { audit: auditBlock });
    expect(blocks.sinks).toEqual({});
  });

  it("drops trashed subjects from the search block", async () => {
    const remove = vi.fn(() => AsyncResult.ok(true));
    const refresh = vi.fn(() => AsyncResult.ok(true));

    const search = defineBlock({
      name: "search",
      create: (_options: BlockContext) => ({ remove, refresh }),
      provides: { sink: (client) => searchSink(client) },
      category: "work",
    });

    const blocks = createBlocks({ transport }, { search });
    await blocks.sinks.search?.send([
      cloudEvent("subject.trashed", { subjectType: "task", subjectId: "t1" }),
      cloudEvent("subject.restored", { subjectType: "task", subjectId: "t2" }),
    ]);
    expect(remove).toHaveBeenCalledWith("task", "t1");
    expect(refresh).toHaveBeenCalledWith("task", "t2");
  });

  it("rolls metrics up for the events in the metrics block's sink option", async () => {
    const blocks = createBlocks(
      { transport },
      {
        metrics: metricsBlock.with({
          sink: {
            on: { "time_entry.recorded": "time_tracked" },
            time: () => "2026-09-28T09:00:00Z",
          },
        }),
      },
    );

    const rollup = vi
      .spyOn(blocks.metrics, "rollup")
      .mockImplementation(() => AsyncResult.ok(1));

    await blocks.sinks.metrics?.send([cloudEvent("time_entry.recorded", {})]);
    expect(rollup.mock.calls[0]?.[0]).toMatchObject({ metric: "time_tracked" });
    expect(rollup.mock.calls[0]?.[0]?.since?.toString()).toBe(
      "2026-09-28T09:00:00Z",
    );
  });

  it("leaves the metrics sink out without the sink option", () => {
    const blocks = createBlocks({ transport }, { metrics: metricsBlock });
    expect(blocks.sinks).toEqual({});
  });
});

describe("createBlocks hooks", () => {
  it("wraps each named block with its hooks", async () => {
    const before = vi.fn(() =>
      dbError("forbidden", "Organizations are created by support"),
    );

    const blocks = createBlocks(
      { transport, hooks: { organizations: { create: { before } } } },
      { organizations: organizationsBlock, audit: auditBlock },
    );

    expect(await blocks.organizations.create({ name: "Acme" })).toMatchObject({
      ok: false,
      error: { kind: "forbidden" },
    });
    expect(before).toHaveBeenCalledWith([{ name: "Acme" }], {
      block: "organizations",
      method: "create",
    });
    blocks.close();
  });

  it("builds ports from the hooked clients", async () => {
    const send = vi.fn(() => "sent");
    const before = vi.fn(() => undefined);
    const seen: Record<string, unknown>[] = [];
    createBlocks(
      { transport, hooks: { notifications: { send: { before } } } },
      {
        notifications: notifier(send),
        recorder: recorder(seen, { notifier: "optional" }),
      },
    );
    const port = seen[0]?.["notifier"] as Notifier;
    await port.send("x", { recipients: [], tenant: "o", key: "k", data: {} });
    expect(before).toHaveBeenCalledTimes(1);
    expect(send).toHaveBeenCalledTimes(1);
  });
});

describe("createBlocks", () => {
  it("builds each block with the shared options and types the result", () => {
    const blocks = createBlocks(
      { transport },
      { organizations: organizationsBlock, audit: auditBlock },
    );

    expect(typeof blocks.organizations.create).toBe("function");
    expect(typeof blocks.audit.sink).toBe("function");
    expectTypeOf(blocks.organizations).toEqualTypeOf<
      ReturnType<NonNullable<(typeof organizationsBlock)["create"]>>
    >();
    blocks.close();
  });

  it("builds rate-limit over the shared transport", async () => {
    const calls: [string, string, Record<string, unknown>][] = [];

    const blocks = createBlocks(
      {
        transport: {
          async call(schema, fn, args) {
            calls.push([schema, fn, { ...args }]);

            return { allowed: true, remaining: 4, retry_after: 0 };
          },
        },
      },
      { "rate-limit": rateLimitBlock },
    );

    expect(await blocks["rate-limit"].check("api", "key-1").orThrow()).toEqual({
      allowed: true,
      remaining: 4,
      retryAfter: 0,
    });
    expect(calls).toEqual([
      [
        "better_supabase",
        "check_rate_limit",
        {
          scope: "api",
          key: "key-1",
          max_requests: undefined,
          period: undefined,
        },
      ],
    ]);
    blocks.close();
  });

  it("skips blocks with only SQL", () => {
    const blocks = createBlocks({ transport }, { tenant: tenantBlock });
    expect(blocks).not.toHaveProperty("tenant");
  });

  it("passes credentials, events and consumed ports, never unconsumed ones", () => {
    const credentials = vaultCredentials({ transport });
    const events = new EventHub();
    const seen: Record<string, unknown>[] = [];

    const files = defineBlock({
      name: "ai-files",
      create: (_options: BlockContext) => fakeFiles,
      provides: { files: (client) => client },
      category: "ai",
    });

    createBlocks(
      { transport, credentials, events },
      {
        knowledge: recorder(seen, { files: "optional" }),
        aiFiles: files,
        connectors: recorder(seen),
      },
    );
    expect(seen[0]).toMatchObject({
      transport,
      credentials,
      events,
      files: fakeFiles,
    });
    expect(seen[1]).toMatchObject({ transport, credentials, events });
    expect(seen[1]).not.toHaveProperty("files");
  });

  it("passes `with` settings over the generated config", () => {
    const seen: Record<string, unknown>[] = [];
    createBlocks(
      {
        transport,
        config: { recorder: { schema: "better_supabase", options: {} } },
      },
      { a: recorder(seen).with({ schema: "own", extra: 1 }) },
    );
    expect(seen[0]).toMatchObject({ schema: "own", extra: 1 });
  });

  it("passes each block its generated schema and shared options by block name", () => {
    const seen: Record<string, unknown>[] = [];
    createBlocks(
      {
        transport,
        config: {
          recorder: {
            schema: "better_supabase",
            api: "api",
            options: { requireScan: false },
          },
        },
      },
      { mine: recorder(seen) },
    );
    expect(seen[0]).toMatchObject({ schema: "api", requireScan: false });
  });

  it("uses the module schema when the generated entry has no API schema", () => {
    const seen: Record<string, unknown>[] = [];
    createBlocks(
      {
        transport,
        config: { recorder: { schema: "app_blocks", options: {} } },
      },
      { mine: recorder(seen) },
    );
    expect(seen[0]).toMatchObject({ schema: "app_blocks" });
  });

  it("hands ai-tasks the notifier port and its notification type", () => {
    const seen: Record<string, unknown>[] = [];
    const send = vi.fn();
    createBlocks(
      { transport },
      {
        aiTasks: recorder(seen, { notifier: "optional" }).with({
          notification: "ai_task.finished",
        }),
        notifications: notifier(send),
      },
    );
    expect(seen[0]).toMatchObject({ notification: "ai_task.finished" });
    expect(seen[0]?.["notifier"]).toHaveProperty("send");
  });

  it("wires reminders to the notifier with their notification type", async () => {
    const send = vi.fn(() => Promise.resolve("n1"));

    const blocks = createBlocks(
      {
        transport: rpcTransport({
          schema: () => ({
            rpc: () => Promise.resolve({ data: true, error: null }),
          }),
        }),
      },
      {
        reminders: remindersBlock.with({
          notification: "reminder.due",
          audience: (_subject, users) => users,
        }),
        notifications: notifier(send),
      },
    );

    await blocks.reminders
      .deliver({
        reminderId: "r1",
        occurrenceAt: "2026-10-14T09:00:00Z",
        organizationId: "o1",
        userId: "u1",
        subjectType: "task",
        subjectId: "42",
      })
      .orThrow();
    expect(send).toHaveBeenCalledWith("reminder.due", {
      recipients: ["u1"],
      tenant: "o1",
      key: "reminder:r1:2026-10-14T09:00:00Z",
      subject: { type: "task", id: "42" },
      data: { reminderId: "r1", occurrenceAt: "2026-10-14T09:00:00Z" },
    });
  });

  it("refuses two providers of one port and a missing required port", () => {
    expect(() =>
      createBlocks(
        { transport },
        { a: notifier(vi.fn()), b: notifier(vi.fn()) },
      ),
    ).toThrow(/"a" and "b" both provide the notifier port/);
    expect(() =>
      createBlocks(
        { transport },
        { needs: recorder([], { notifier: "required" }) },
      ),
    ).toThrow(/"needs" needs a block that provides the notifier port/);
  });

  it("forwards block events to audit until close", async () => {
    const events = new EventHub();
    const sent: CloudEvent[] = [];

    const blocks = createBlocks(
      {
        transport,
        events,
        audit: { send: (batch) => void sent.push(...batch) },
      },
      {},
    );

    const created = { organizationId: "o1" };
    emitBlockEvent<OrganizationsEvents>(
      events,
      "organization.created",
      created,
    );
    await events.settled();
    expect(sent).toHaveLength(1);
    expect(sent[0]).toMatchObject({
      source: BLOCK_EVENT_SOURCE,
      type: "dev.better-supabase.organization.created",
    });
    blocks.close();
    emitBlockEvent<OrganizationsEvents>(
      events,
      "organization.created",
      created,
    );
    await events.settled();
    expect(sent).toHaveLength(1);
  });

  it("needs events to forward to audit", () => {
    expect(() =>
      createBlocks({ transport, audit: { send: () => undefined } }, {}),
    ).toThrow(/needs `events`/);
  });

  it("reports a block that consumes its own provider through a cycle", () => {
    const loop = defineBlock({
      name: "loop",
      create: (options: { readonly files?: AiFiles }): Notifier => {
        void options.files;

        return { send: vi.fn() };
      },
      consumes: { files: "optional" },
      provides: { notifier: (client) => client },
      category: "collaboration",
    });

    const files = defineBlock({
      name: "files",
      create: (options: { readonly notifier?: Notifier }): AiFiles => {
        void options.notifier;

        return fakeFiles;
      },
      consumes: { notifier: "optional" },
      provides: { files: (client) => client },
      category: "ai",
    });

    expect(() => createBlocks({ transport }, { loop, files })).toThrow(
      /depends on itself/,
    );
  });
});

describe("defineBlocks", () => {
  const app = defineEvents({
    "invoice.sent": event<{ readonly invoiceId: string }>(),
  });

  const config = {
    organizations: { schema: "better_supabase", api: "api", options: {} },
  } as const;

  const set = defineBlocks(
    config,
    { organizations: organizationsBlock, audit: auditBlock },
    app,
  );

  it("lists every block's events and the app's", () => {
    expect(set.events.types).toContain("organization.created");
    expect(set.events.types).toContain("audit.revealed");
    expect(set.events.types).toContain("invoice.sent");
  });

  it("types events from the blocks and the app, and listens to them", async () => {
    const events = new EventHub();
    const seen: string[] = [];

    const stop = set.on({ events }, "invoice.*", (sent) => {
      expectTypeOf(sent.data.invoiceId).toBeString();
      seen.push(sent.data.invoiceId);
    });

    set.on({ events }, "organization.created", (created) => {
      expectTypeOf(created.data.organizationId).toBeString();
      seen.push(created.type);
    });
    emitBlockEvent<{ readonly "invoice.sent": { invoiceId: string } }>(
      events,
      "invoice.sent",
      { invoiceId: "i1" },
    );
    emitBlockEvent<OrganizationsEvents>(events, "organization.created", {
      organizationId: "o1",
    });
    emitBlockEvent(events, "unknown.type", {});
    stop();
    emitBlockEvent<{ readonly "invoice.sent": { invoiceId: string } }>(
      events,
      "invoice.sent",
      { invoiceId: "i2" },
    );
    await events.settled();
    expect(seen).toEqual(["i1", "organization.created"]);
  });

  it("calls the functions by the generated names", async () => {
    const calls: string[] = [];

    const named = defineBlocks(
      {
        organizations: {
          schema: "better_supabase",
          options: {},
          naming: { tenant: "workspace" },
        },
      },
      { organizations: organizationsBlock },
    );

    const blocks = named.create({
      transport: {
        async call(_schema, fn) {
          calls.push(fn);

          return [{ workspace_id: "w1", role: "owner" }];
        },
      },
    });

    await blocks.organizations.mine();
    expect(calls).toEqual(["list_my_workspaces"]);
    blocks.close();
  });

  it("creates the blocks with the generated config", () => {
    const blocks = set.create({ transport });
    expect(set.config).toBe(config);
    expect(typeof blocks.organizations.create).toBe("function");
    blocks.close();
  });
});

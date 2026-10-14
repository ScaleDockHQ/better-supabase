import { describe, expect, expectTypeOf, it, vi } from "vitest";

import type { AiFiles } from "../../src/blocks/ai-files/index.ts";
import type { AiTaskOutcome } from "../../src/blocks/ai-tasks/index.ts";
import type { BlockContext } from "../../src/blocks/index.ts";
import type { CloudEvent } from "../../src/events/index.ts";

import { createAuditLog } from "../../src/blocks/audit/index.ts";
import {
  BLOCK_EVENT_SOURCE,
  createBlocks,
  rpcTransport,
} from "../../src/blocks/index.ts";
import { createOrganizations } from "../../src/blocks/organizations/index.ts";
import { emitBlockEvent } from "../../src/core/block-events.ts";
import { dbError } from "../../src/core/errors.ts";
import { EventHub } from "../../src/core/events.ts";
import { AsyncResult } from "../../src/core/result.ts";
import { vaultCredentials } from "../../src/credentials/index.ts";

const transport = rpcTransport({
  schema: () => ({
    rpc: () => Promise.resolve({ data: null, error: null }),
  }),
});

const fakeFiles = {} as AiFiles;

const event = (type: string, data: unknown): CloudEvent => ({
  specversion: "1.0",
  id: type,
  source: "/test",
  type: `dev.better-supabase.${type}`,
  time: "2026-10-14T10:00:00Z",
  data,
});

describe("createBlocks sinks", () => {
  it("has none without the search and metrics blocks", () => {
    const blocks = createBlocks({ transport }, { audit: createAuditLog });
    expect(blocks.sinks).toEqual({});
  });

  it("drops trashed subjects from the search block", async () => {
    const remove = vi.fn(() => AsyncResult.ok(true));
    const refresh = vi.fn(() => AsyncResult.ok(true));
    const blocks = createBlocks(
      { transport },
      { search: () => ({ remove, refresh }), trash: () => ({}) },
    );
    await blocks.sinks.search?.send([
      event("subject.trashed", { subjectType: "task", subjectId: "t1" }),
      event("subject.restored", { subjectType: "task", subjectId: "t2" }),
    ]);
    expect(remove).toHaveBeenCalledWith("task", "t1");
    expect(refresh).toHaveBeenCalledWith("task", "t2");
    expect(blocks.sinks.metrics).toBeUndefined();
  });

  it("rolls metrics up for the events in metricEvents", async () => {
    const rollup = vi.fn((_request: { readonly metric: string }) =>
      AsyncResult.ok(1),
    );
    const blocks = createBlocks(
      { transport, metricEvents: { "order.placed": ["orders", "revenue"] } },
      { metrics: () => ({ rollup }) },
    );
    await blocks.sinks.metrics?.send([event("order.placed", {})]);
    expect(rollup.mock.calls.map(([request]) => request.metric)).toEqual([
      "orders",
      "revenue",
    ]);
  });

  it("refuses metricEvents without a metrics block and blocks of the wrong shape", () => {
    expect(() =>
      createBlocks({ transport, metricEvents: {} }, { audit: createAuditLog }),
    ).toThrow(/needs a `metrics` block/);
    expect(() => createBlocks({ transport }, { search: () => ({}) })).toThrow(
      /search block has no remove/,
    );
    expect(() => createBlocks({ transport }, { metrics: () => 1 })).toThrow(
      /metrics block has no rollup/,
    );
  });
});

describe("createBlocks hooks", () => {
  it("wraps each named block with its hooks", async () => {
    const before = vi.fn(() =>
      dbError("forbidden", "Organizations are created by support"),
    );
    const blocks = createBlocks(
      { transport, hooks: { organizations: { create: { before } } } },
      { organizations: createOrganizations, audit: createAuditLog },
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
});

describe("createBlocks", () => {
  it("builds each block with the shared options and types the result", () => {
    const blocks = createBlocks(
      { transport, schema: "api" },
      { organizations: createOrganizations, audit: createAuditLog },
    );
    expect(typeof blocks.organizations.create).toBe("function");
    expect(typeof blocks.audit.sink).toBe("function");
    expectTypeOf(blocks.organizations).toEqualTypeOf<
      ReturnType<typeof createOrganizations>
    >();
    blocks.close();
  });

  it("wires aiFiles, credentials and events into the siblings", () => {
    const credentials = vaultCredentials({ transport });
    const events = new EventHub();
    const seen: BlockContext[] = [];
    const aiFiles = vi.fn(() => fakeFiles);
    createBlocks(
      { transport, credentials, events },
      {
        knowledge: (context) => seen.push(context),
        aiFiles,
        connectors: (context) => seen.push(context),
      },
    );
    expect(aiFiles).toHaveBeenCalledTimes(1);
    expect(aiFiles.mock.calls[0]).not.toHaveProperty("0.files");
    for (const context of seen)
      expect(context).toMatchObject({
        transport,
        credentials,
        events,
        files: fakeFiles,
      });
  });

  it("sends the ai-task notification through the notifications block", async () => {
    const send = vi.fn(() => Promise.resolve("n1"));
    let notify: BlockContext["notify"];
    createBlocks(
      { transport, aiTaskNotification: "ai_task.finished" },
      {
        aiTasks: (context) => (notify = context.notify),
        notifications: () => ({ send }),
      },
    );
    const outcome = {
      task: { id: "t1", userId: "u1", organizationId: "o1" },
      run: { id: "r1" },
      ok: false,
      error: "boom",
    } as AiTaskOutcome;
    await notify?.(outcome);
    expect(send).toHaveBeenCalledWith("ai_task.finished", {
      recipients: ["u1"],
      tenant: "o1",
      key: "ai-task-run:r1",
      data: { taskId: "t1", runId: "r1", ok: false, error: "boom" },
    });
  });

  it("wires reminders to notifications with reminderNotification", async () => {
    const send = vi.fn(() => Promise.resolve("n1"));
    let notifyDelivery: BlockContext["notifyDelivery"];
    createBlocks(
      { transport, reminderNotification: "reminder.due" },
      {
        reminders: (context) => (notifyDelivery = context.notifyDelivery),
        notifications: () => ({ send }),
      },
    );
    await notifyDelivery?.({
      reminderId: "r1",
      occurrenceAt: "2026-10-14T09:00:00Z",
      organizationId: "o1",
      userId: "u1",
      subjectType: "task",
      subjectId: "42",
    });
    await notifyDelivery?.({
      reminderId: "r2",
      occurrenceAt: "2026-10-14T09:00:00Z",
      organizationId: "o1",
    });
    expect(send).toHaveBeenNthCalledWith(1, "reminder.due", {
      recipients: ["u1"],
      tenant: "o1",
      key: "reminder:r1:2026-10-14T09:00:00Z",
      subject: { type: "task", id: "42" },
      data: { reminderId: "r1", occurrenceAt: "2026-10-14T09:00:00Z" },
    });
    expect(send).toHaveBeenNthCalledWith(2, "reminder.due", {
      recipients: [],
      tenant: "o1",
      key: "reminder:r2:2026-10-14T09:00:00Z",
      data: { reminderId: "r2", occurrenceAt: "2026-10-14T09:00:00Z" },
    });
  });

  it("leaves notifyDelivery out without notifications", () => {
    const seen: BlockContext[] = [];
    createBlocks(
      { transport, reminderNotification: "reminder.due" },
      { reminders: (context) => seen.push(context) },
    );
    expect(seen[0]).not.toHaveProperty("notifyDelivery");
  });

  it("leaves notify out without a notification type", () => {
    const seen: BlockContext[] = [];
    createBlocks(
      { transport },
      {
        aiTasks: (context) => seen.push(context),
        notifications: () => ({ send: vi.fn() }),
      },
    );
    expect(seen[0]).not.toHaveProperty("notify");
  });

  it("rejects a notifications block that cannot send", () => {
    let notify: BlockContext["notify"];
    createBlocks(
      { transport, aiTaskNotification: "done" },
      {
        aiTasks: (context) => (notify = context.notify),
        notifications: () => 1,
      },
    );
    expect(() => notify?.({} as AiTaskOutcome)).toThrow(/no send method/);
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
    const denied = { adminId: "a1", targetUserId: "u1" };
    emitBlockEvent(events, "support.denied", denied);
    await events.settled();
    expect(sent).toHaveLength(1);
    expect(sent[0]).toMatchObject({
      source: BLOCK_EVENT_SOURCE,
      type: "dev.better-supabase.support.denied",
    });
    blocks.close();
    emitBlockEvent(events, "support.denied", denied);
    await events.settled();
    expect(sent).toHaveLength(1);
  });

  it("needs events to forward to audit", () => {
    expect(() =>
      createBlocks({ transport, audit: { send: () => undefined } }, {}),
    ).toThrow(/needs `events`/);
  });

  it("reports a block that depends on itself", () => {
    const outcome = {
      task: { id: "t1", userId: "u1", organizationId: "o1" },
      run: { id: "r1" },
      ok: true,
    } as AiTaskOutcome;
    expect(() =>
      createBlocks(
        { transport, aiTaskNotification: "done" },
        {
          notifications: (context) => {
            context.notify?.(outcome);
            return { send: vi.fn() };
          },
        },
      ),
    ).toThrow(/depends on itself/);
  });
});

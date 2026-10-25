import { describe, expect, it, vi } from "vitest";

import type { BlockTransport } from "../../src/core/block-transport.ts";

import { ok } from "../../src/core/result.ts";
import {
  notificationRecipientsRoute,
  powersyncNotificationsTransport,
  powersyncTopicPort,
} from "../../src/powersync/index.ts";
import { schema } from "../fixtures/generated-camel.ts";
import { createSqlite } from "../fixtures/sqlite.ts";

const ORG = "org-1";
const OTHER = "org-2";

const DDL = [
  `create table notification_events (id text primary key, organization_id text, type text not null,
    data text, actor_id text, subject_type text, subject_id text, subject_label text, summary text,
    action_path text, actions text, priority text, created_at text, region text)`,
  `create table notification_recipients (id text primary key, event_id text not null, user_id text,
    organization_id text, created_at text, read_at text, resolved_at text, resolution text,
    dismissed_at text)`,
];

function setup() {
  const sqlite = createSqlite(schema.meta, DDL);

  const event = sqlite.sqlite.prepare(
    "insert into notification_events (id, organization_id, type, data, subject_type, subject_id, summary, actions, region) values (?, ?, ?, ?, ?, ?, ?, ?, ?)",
  );

  const recipient = sqlite.sqlite.prepare(
    "insert into notification_recipients (id, event_id, user_id, organization_id, created_at, read_at, dismissed_at) values (?, ?, 'u1', ?, ?, ?, ?)",
  );

  event.run(
    "e1",
    ORG,
    "invoice.due",
    '{"amount":5}',
    "invoice",
    "i1",
    "Invoice due",
    "[]",
    "eu",
  );
  event.run(
    "e2",
    ORG,
    "comment.added",
    "{}",
    "post",
    "p1",
    "New comment",
    "[]",
    "eu",
  );
  event.run(
    "e3",
    OTHER,
    "invoice.due",
    "{}",
    null,
    null,
    "Other org",
    "[]",
    "us",
  );
  recipient.run("r1", "e1", ORG, "2026-01-02 10:00:00.000000Z", null, null);
  recipient.run(
    "r2",
    "e2",
    ORG,
    "2026-01-02 11:00:00.000000Z",
    "2026-01-02 11:30:00.000000Z",
    null,
  );
  recipient.run("r3", "e3", OTHER, "2026-01-02 12:00:00.000000Z", null, null);
  recipient.run(
    "r4",
    "e1",
    ORG,
    "2026-01-01 09:00:00.000000Z",
    null,
    "2026-01-01 10:00:00.000000Z",
  );

  const serverCall = vi.fn(() => Promise.resolve("server"));
  const server: BlockTransport = { call: serverCall };
  const transport = powersyncNotificationsTransport(sqlite.db, { server });

  return { ...sqlite, server, serverCall, transport };
}

const ids = (value: unknown): unknown[] =>
  (value as { id: unknown }[]).map((item) => item.id);

describe("powersyncNotificationsTransport", () => {
  it("lists the feed newest first, without dismissed rows, in PostgREST shape", async () => {
    const { transport } = setup();

    const items = await transport.call(
      "better_supabase",
      "list_notifications",
      { max_items: 50 },
    );

    expect(ids(items)).toEqual(["r3", "r2", "r1"]);
    expect((items as Record<string, unknown>[])[2]).toMatchObject({
      id: "r1",
      event_id: "e1",
      type: "invoice.due",
      data: { amount: 5 },
      tenant: ORG,
      created_at: "2026-01-02T10:00:00+00:00",
      read_at: null,
      actions: [],
      fields: { region: "eu" },
    });
  });

  it("filters by tenant, status, type, search and the cursor", async () => {
    const { transport } = setup();

    const list = (args: Record<string, unknown>) =>
      transport.call("better_supabase", "list_notifications", args).then(ids);

    await expect(list({ tenant: ORG })).resolves.toEqual(["r2", "r1"]);
    await expect(list({ status: "unread" })).resolves.toEqual(["r3", "r1"]);
    await expect(list({ status: "settled" })).resolves.toEqual(["r4"]);
    await expect(list({ types: ["comment.added"] })).resolves.toEqual(["r2"]);
    await expect(list({ search: "invoice" })).resolves.toEqual(["r3", "r1"]);
    await expect(list({ search: "100%" })).resolves.toEqual([]);
    await expect(
      list({ before: "2026-01-02T11:00:00Z", before_id: "r2" }),
    ).resolves.toEqual(["r1"]);
    await expect(list({ max_items: 1 })).resolves.toEqual(["r3"]);
  });

  it("pages with a total and counts unread and actionable rows", async () => {
    const { transport } = setup();

    await expect(
      transport.call("better_supabase", "notification_page", {
        max_items: 1,
        skip: 1,
      }),
    ).resolves.toMatchObject({ total: 3, items: [{ id: "r2" }] });
    await expect(
      transport.call("better_supabase", "notification_counts", {
        tenant: ORG,
        actionable: ["invoice.due"],
      }),
    ).resolves.toEqual({ unread: 1, actionable: 1, actionable_subjects: 1 });
  });

  it("marks read, unread and dismissed in one write the upload queue keeps", async () => {
    const { transport, sqlite } = setup();

    const read = (id: string) =>
      sqlite
        .prepare(
          "select read_at, dismissed_at from notification_recipients where id = ?",
        )
        .get(id);

    await expect(
      transport.call("better_supabase", "mark_notifications_read", {
        ids: null,
        tenant: ORG,
      }),
    ).resolves.toMatchObject({ count: 1, items: [{ id: "r1" }] });
    expect(read("r1")).toMatchObject({ read_at: expect.any(String) });
    expect(read("r3")).toMatchObject({ read_at: null });

    await expect(
      transport.call("better_supabase", "mark_notifications_unread", {
        ids: ["r1"],
      }),
    ).resolves.toMatchObject({ count: 1 });
    expect(read("r1")).toMatchObject({ read_at: null });

    await expect(
      transport.call("better_supabase", "dismiss_notifications", {
        ids: ["r3", "r4"],
      }),
    ).resolves.toMatchObject({ count: 1, items: [{ id: "r3" }] });
    expect(read("r3")).toMatchObject({
      dismissed_at: expect.any(String),
      read_at: expect.any(String),
    });
  });

  it("gets one item and sends every other function to the server", async () => {
    const { transport, serverCall } = setup();

    await expect(
      transport.call("better_supabase", "get_notification", { id: "r2" }),
    ).resolves.toMatchObject({
      id: "r2",
      read_at: "2026-01-02T11:30:00+00:00",
    });
    await expect(
      transport.call("better_supabase", "get_notification", { id: "nope" }),
    ).resolves.toBeNull();
    await expect(
      transport.call("better_supabase", "resolve_notifications", { ids: [] }),
    ).resolves.toBe("server");
    expect(serverCall).toHaveBeenCalledWith(
      "better_supabase",
      "resolve_notifications",
      { ids: [] },
    );
  });

  it("follows renamed functions and tables", async () => {
    const { db, server } = setup();

    const transport = powersyncNotificationsTransport(db, {
      server,
      functions: { list_notifications: "inbox_list" },
    });

    await expect(
      transport.call("api", "inbox_list", { tenant: OTHER }),
    ).resolves.toHaveLength(1);
    await expect(transport.call("api", "list_notifications", {})).resolves.toBe(
      "server",
    );
  });
});

describe("notificationRecipientsRoute", () => {
  const writes = () => {
    const calls: unknown[] = [];

    const reply = (call: unknown) => {
      calls.push(call);

      return Promise.resolve(ok(null));
    };

    return {
      calls,
      notifications: {
        markRead: (options: { ids: readonly string[] }) =>
          reply(["read", options.ids]),
        markUnread: (options: { ids: readonly string[] }) =>
          reply(["unread", options.ids]),
        dismiss: (ids: readonly string[]) => reply(["dismiss", ids]),
      },
    };
  };

  it("replays read, unread and dismiss through the server functions", async () => {
    const { calls, notifications } = writes();
    const route = notificationRecipientsRoute(notifications);

    const patch = (opData: Record<string, unknown>) =>
      route({
        op: "PATCH",
        table: "notification_recipients",
        id: "r1",
        opData,
      });

    await patch({ read_at: "2026-01-02T10:00:00Z" });
    await patch({ read_at: null });
    await patch({
      dismissed_at: "2026-01-02T10:00:00Z",
      read_at: "2026-01-02T10:00:00Z",
    });
    await patch({ resolution: "{}" });

    expect(calls).toEqual([
      ["read", ["r1"]],
      ["unread", ["r1"]],
      ["dismiss", ["r1"]],
    ]);
  });

  it("rejects inserts and deletes, which only the server makes", async () => {
    const route = notificationRecipientsRoute(writes().notifications);

    const result = await route({
      op: "DELETE",
      table: "notification_recipients",
      id: "r1",
    });

    expect(result).toMatchObject({ ok: false, error: { kind: "unsupported" } });
  });
});

describe("powersyncTopicPort", () => {
  it("refreshes the feed when the notification tables change", async () => {
    const { db, transport } = setup();
    const onMessage = vi.fn();
    const onStatus = vi.fn();

    const handle = powersyncTopicPort(db)("user:u1", {
      onMessage,
      onRejoin: () => undefined,
      onStatus,
    });

    expect(onStatus).toHaveBeenCalledWith("subscribed");

    await transport.call("better_supabase", "mark_notifications_read", {
      ids: ["r1"],
    });
    expect(onMessage).toHaveBeenCalledOnce();

    handle.leave();
    handle.leave();
    await transport.call("better_supabase", "mark_notifications_unread", {
      ids: ["r1"],
    });
    expect(onMessage).toHaveBeenCalledOnce();
  });
});

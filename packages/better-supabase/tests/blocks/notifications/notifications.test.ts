import type { StandardSchemaV1 } from "@standard-schema/spec";

import * as v from "valibot";
import { describe, expect, it, vi } from "vitest";

import type { NotificationChannel } from "../../../src/blocks/notifications/index.ts";
import type { BlockTransport } from "../../../src/core/block-transport.ts";

import { createNotifications } from "../../../src/blocks/notifications/index.ts";
import { dbError } from "../../../src/core/errors.ts";
import { EventHub } from "../../../src/core/events.ts";
import { testNotificationChannel } from "../../../src/testing/index.ts";

const titled: StandardSchemaV1<{ title: string }> = {
  "~standard": {
    version: 1,
    vendor: "test",
    validate: (value) =>
      typeof value === "object" &&
      value !== null &&
      "title" in value &&
      typeof value.title === "string"
        ? { value: { title: value.title } }
        : { issues: [{ message: "title is required", path: ["title"] }] },
  },
};

const types = { "task.assigned": titled, "approval.requested": titled };

type Handler = (args: Readonly<Record<string, unknown>>) => unknown;

function fakeTransport(handlers: Record<string, Handler> = {}) {
  const calls: { schema: string; fn: string; args: Record<string, unknown> }[] =
    [];
  const transport: BlockTransport = {
    async call(schema, fn, args) {
      calls.push({ schema, fn, args: { ...args } });
      const handler = handlers[fn];
      return handler ? handler(args) : null;
    },
  };
  return { transport, calls };
}

const row = (overrides: Record<string, unknown> = {}) => ({
  id: "r1",
  event_id: "e1",
  type: "task.assigned",
  data: { title: "Ship it" },
  tenant: "organization_1",
  actor_id: "u0",
  subject_type: "task",
  subject_id: "42",
  subject_label: "Ship it",
  summary: "Assigned",
  action_path: "/tasks/42",
  priority: "normal",
  created_at: "2026-01-01T00:00:00Z",
  read_at: null,
  resolved_at: null,
  ...overrides,
});

describe("createNotifications().sink", () => {
  const event = (type: string, extra: Record<string, unknown> = {}) => ({
    specversion: "1.0" as const,
    id: `id-${type}`,
    source: "better-supabase/organizations",
    type: `dev.better-supabase.${type}`,
    data: { organizationId: "organization_1", userId: "u1" },
    ...extra,
  });

  it("sends a notification per mapped event, keyed by the event id", async () => {
    const { transport, calls } = fakeTransport({
      send_notification: () => ({ id: "e1", recipients: ["u1"] }),
    });
    const seen: string[] = [];
    const sink = createNotifications({ transport, types }).sink({
      map(cloudEvent) {
        seen.push(cloudEvent.type);
        return cloudEvent.type === "organization.member_added"
          ? {
              type: "task.assigned",
              recipients: ["u1"],
              data: { title: "Welcome" },
            }
          : null;
      },
    });
    await sink.send([
      event("organization.member_added", { partitionkey: "organization_1" }),
      event("organization.updated"),
    ]);
    expect(seen).toEqual(["organization.member_added", "organization.updated"]);
    expect(calls).toHaveLength(1);
    expect(calls[0]?.args).toMatchObject({
      notification: {
        type: "task.assigned",
        recipients: ["u1"],
        tenant: "organization_1",
        key: "id-organization.member_added",
        data: { title: "Welcome" },
      },
    });
  });

  it("keeps the mapped key and tenant, and rejects when the send fails", async () => {
    const { transport, calls } = fakeTransport();
    const sink = createNotifications({ transport, types }).sink({
      typePrefix: "",
      map: async (cloudEvent) => ({
        type: "task.assigned",
        tenant: "organization_2",
        key: `own-${cloudEvent.type}`,
        data: { title: "Hi" },
      }),
    });
    await sink.send([event("x", { partitionkey: "organization_1" })]);
    expect(calls[0]?.args).toMatchObject({
      notification: {
        tenant: "organization_2",
        key: "own-dev.better-supabase.x",
      },
    });
    const failing = createNotifications({
      transport: {
        async call() {
          throw Object.assign(new Error("denied"), { code: "42501" });
        },
      },
      types,
    }).sink({
      map: () => ({ type: "task.assigned", data: { title: "Hi" } }),
    });
    await expect(failing.send([event("x")])).rejects.toThrow("denied");
  });
});

describe("createNotifications().send", () => {
  it("validates the data, calls notify, emits and runs onSent", async () => {
    const { transport, calls } = fakeTransport({
      send_notification: () => ({ id: "e1", recipients: ["u1", "u3"] }),
    });
    const events = new EventHub();
    const seen: unknown[] = [];
    events.on("block", (event) => seen.push([event.type, event.data]));
    const onSent = vi.fn();
    const notifications = createNotifications({
      transport,
      types,
      schema: "app",
      events,
      onSent,
    });
    const sent = await notifications.send("task.assigned", {
      recipients: ["u1"],
      tenant: "organization_1",
      subject: { type: "task", id: "42", label: "Ship it" },
      data: { title: "Ship it" },
      key: "task-42",
    });
    expect(sent).toMatchObject({
      ok: true,
      data: { id: "e1", recipients: ["u1", "u3"] },
    });
    expect(calls[0]).toMatchObject({
      schema: "app",
      fn: "send_notification",
      args: {
        notification: {
          type: "task.assigned",
          recipients: ["u1"],
          tenant: "organization_1",
          subject_type: "task",
          subject_id: "42",
          subject_label: "Ship it",
          key: "task-42",
          data: { title: "Ship it" },
        },
      },
    });
    expect(seen).toEqual([
      [
        "notification.created",
        {
          notificationId: "e1",
          type: "task.assigned",
          recipientIds: ["u1", "u3"],
        },
      ],
    ]);
    expect(onSent).toHaveBeenCalledWith({
      id: "e1",
      type: "task.assigned",
      tenant: "organization_1",
      recipients: ["u1", "u3"],
    });
  });

  it("subscribes another member only when absent", async () => {
    const { transport, calls } = fakeTransport({
      set_notification_subscription: () => null,
    });
    await createNotifications({ transport, types })
      .subscribe({
        subject: { type: "task", id: "42" },
        level: "participating",
        tenant: "organization_1",
        userId: "u2",
        ifAbsent: true,
      })
      .orThrow();
    expect(calls[0]).toMatchObject({
      fn: "set_notification_subscription",
      args: { member: "u2", if_absent: true, level: "participating" },
    });
  });

  it("passes watchers and exclude to notify", async () => {
    const { transport, calls } = fakeTransport({
      send_notification: () => ({ id: "e2" }),
    });
    await createNotifications({ transport, types })
      .send("task.assigned", {
        recipients: ["u1"],
        subject: { type: "task", id: "42" },
        data: { title: "Ship it" },
        watchers: false,
        exclude: ["u2"],
      })
      .orThrow();
    expect(calls[0]).toMatchObject({
      args: { notification: { watchers: false, exclude: ["u2"] } },
    });
  });

  it("rejects unknown types and invalid data without calling the database", async () => {
    const { transport, calls } = fakeTransport();
    const notifications = createNotifications({ transport, types });
    const unknown = await notifications.send(
      // @ts-expect-error -- not a configured type
      "nope",
      { data: {} },
    );
    expect(unknown).toMatchObject({
      ok: false,
      error: { kind: "validation", hint: "NOTIFICATION_TYPE_UNKNOWN" },
    });
    const invalid = await notifications.send("task.assigned", {
      // @ts-expect-error -- title is required
      data: {},
    });
    expect(invalid).toMatchObject({ ok: false, error: { kind: "validation" } });
    expect(calls).toHaveLength(0);
  });

  it("returns null without events when nobody is left to notify", async () => {
    const { transport } = fakeTransport({ send_notification: () => null });
    const onSent = vi.fn();
    const notifications = createNotifications({ transport, types, onSent });
    const sent = await notifications.send("task.assigned", {
      data: { title: "x" },
    });
    expect(sent).toMatchObject({ ok: true, data: null });
    expect(onSent).not.toHaveBeenCalled();
  });

  it("maps database errors through the error mappers and onSent failures", async () => {
    const { transport } = fakeTransport({
      send_notification: () => {
        throw Object.assign(new Error("not allowed"), {
          code: "42501",
          hint: "NOTIFICATION_FORBIDDEN",
        });
      },
    });
    const notifications = createNotifications({ transport, types });
    const denied = await notifications.send("task.assigned", {
      data: { title: "x" },
    });
    expect(denied).toMatchObject({
      ok: false,
      error: { kind: "forbidden", hint: "NOTIFICATION_FORBIDDEN" },
    });

    const failing = createNotifications({
      transport: fakeTransport({
        send_notification: () => ({ id: "e1", recipients: [] }),
      }).transport,
      types,
      onSent: () => {
        throw new Error("cache down");
      },
    });
    const sent = await failing.send("task.assigned", { data: { title: "x" } });
    expect(sent.ok).toBe(false);
  });
});

describe("createNotifications reads and writes", () => {
  it("reads one notification and filters on read, resolved and dismissed", async () => {
    const { transport, calls } = fakeTransport({
      get_notification: (args) => (args["id"] === "r1" ? row() : null),
      notification_page: () => ({ items: [], total: 0 }),
      mark_notifications_read: () => null,
    });
    const notifications = createNotifications({
      transport,
      types,
      render: (item, { locale }) => ({
        title: `${locale ?? "en"}: ${item.summary ?? ""}`,
      }),
    });
    expect(
      await notifications.get("r1", { locale: "nl" }).orThrow(),
    ).toMatchObject({ id: "r1", text: { title: "nl: Assigned" } });
    expect(await notifications.get("r9").orThrow()).toBeNull();
    await notifications
      .page({ resolved: true, read: false, dismissed: null })
      .orThrow();
    expect(calls[2]!.args).toMatchObject({
      status: "all",
      read: false,
      resolved: true,
      dismissed: null,
    });
    expect(await notifications.markRead().orThrow()).toEqual({
      count: 0,
      items: [],
    });
  });

  it("lists rendered items and passes the filters", async () => {
    const { transport, calls } = fakeTransport({
      list_notifications: () => [row(), row({ id: "r2", subject_type: null })],
    });
    const notifications = createNotifications({
      transport,
      types,
      render: (item, { locale }) => ({
        title: `${locale ?? "en"}: ${item.summary ?? ""}`,
      }),
    });
    const listed = await notifications.list({
      status: "unread",
      types: ["task.assigned"],
      cursor: Temporal.Instant.from("2026-02-01T00:00:00Z"),
      limit: 10,
      locale: "nl",
    });
    expect(listed.ok).toBe(true);
    const [first, second] = listed.ok ? listed.data : [];
    expect(first).toMatchObject({
      id: "r1",
      eventId: "e1",
      subject: { type: "task", id: "42", label: "Ship it" },
      text: { title: "nl: Assigned" },
      readAt: null,
    });
    expect(first?.createdAt.toString()).toBe("2026-01-01T00:00:00Z");
    expect(second?.subject).toBeNull();
    expect(calls[0]?.args).toEqual({
      tenant: null,
      status: "unread",
      types: ["task.assigned"],
      before: "2026-02-01T00:00:00Z",
      before_id: null,
      max_items: 10,
      subject_types: null,
      search: null,
      read: null,
      resolved: null,
      dismissed: false,
    });
    await notifications.list({ cursor: first! });
    expect(calls[1]?.args).toMatchObject({
      before: "2026-01-01T00:00:00Z",
      before_id: "r1",
    });
  });

  it("pages by offset with a total, search and subject types", async () => {
    const { transport, calls } = fakeTransport({
      notification_page: () => ({ items: [row()], total: 31 }),
    });
    const notifications = createNotifications({
      transport,
      types,
      render: (item) => ({ title: item.summary ?? "" }),
    });
    const page = await notifications
      .page({
        status: "settled",
        subjectTypes: ["task"],
        search: "ship",
        limit: 10,
        offset: 30,
      })
      .orThrow();
    expect(page.total).toBe(31);
    expect(page.items[0]).toMatchObject({
      id: "r1",
      text: { title: "Assigned" },
    });
    expect(calls[0]).toEqual({
      schema: "better_supabase",
      fn: "notification_page",
      args: {
        tenant: null,
        status: "settled",
        types: null,
        subject_types: ["task"],
        search: "ship",
        max_items: 10,
        skip: 30,
        read: null,
        resolved: null,
        dismissed: false,
      },
    });
    const empty = fakeTransport({ notification_page: () => null });
    expect(
      await createNotifications({ transport: empty.transport, types })
        .page()
        .orThrow(),
    ).toEqual({ items: [], total: 0 });
    expect(empty.calls[0]!.args).toMatchObject({ max_items: 50, skip: 0 });
  });

  it("marks unread and reads the caller's subscriptions and preferences", async () => {
    const { transport, calls } = fakeTransport({
      mark_notifications_unread: () => ({
        count: 2,
        items: [row({ id: "r1" }), row({ id: "r2" })],
      }),
      list_notification_subscriptions: () => [
        {
          subject_type: "task",
          subject_id: "42",
          level: "all",
          tenant: "organization_1",
          created_at: "2026-01-01T00:00:00Z",
        },
        { subject_type: "task", subject_id: "43", level: "odd", tenant: null },
      ],
      list_notification_preferences: () => [
        { type: "*", channel: "email", enabled: false, tenant: null },
        "not a row",
      ],
    });
    const notifications = createNotifications({ transport, types });
    expect(
      await notifications
        .markUnread({ ids: ["r1", "r2"], tenant: "organization_1" })
        .orThrow(),
    ).toMatchObject({ count: 2, items: [{ id: "r1" }, { id: "r2" }] });
    const subscriptions = await notifications
      .subscriptions({ tenant: "organization_1", subject: { type: "task" } })
      .orThrow();
    expect(subscriptions).toHaveLength(1);
    expect(subscriptions[0]).toMatchObject({
      subject: { type: "task", id: "42" },
      level: "all",
      tenant: "organization_1",
    });
    expect(subscriptions[0]!.createdAt?.toString()).toBe(
      "2026-01-01T00:00:00Z",
    );
    expect(await notifications.preferences().orThrow()).toEqual([
      { type: "*", channel: "email", enabled: false, tenant: null },
    ]);
    expect(calls.map((call) => [call.fn, call.args])).toEqual([
      [
        "mark_notifications_unread",
        { ids: ["r1", "r2"], tenant: "organization_1" },
      ],
      [
        "list_notification_subscriptions",
        { tenant: "organization_1", subject_type: "task", subject_id: null },
      ],
      ["list_notification_preferences", { tenant: null }],
    ]);
    const odd = fakeTransport({
      list_notification_subscriptions: () => null,
      list_notification_preferences: () => null,
    });
    const quiet = createNotifications({ transport: odd.transport, types });
    expect(await quiet.subscriptions().orThrow()).toEqual([]);
    expect(await quiet.preferences().orThrow()).toEqual([]);
  });

  it("hydrates a page once and adds actor profiles in one call", async () => {
    const { transport, calls } = fakeTransport({
      list_notifications: () => [
        row(),
        row({ id: "r2", actor_id: "u0" }),
        row({ id: "r3", actor_id: null }),
        row({ id: "r4", actor_id: "gone" }),
      ],
      notification_actors: () => ({
        u0: { id: "u0", username: "ada", avatar: null },
        bad: "not a profile",
      }),
    });
    const hydrate = vi.fn(
      (
        items: readonly { actorId: string | null }[],
        _context: { readonly locale?: string },
      ) => ({
        names: new Map(items.map((item) => [item.actorId, "Ada"])),
      }),
    );
    const notifications = createNotifications({
      transport,
      types,
      hydrate,
      render: (item, { hydrated }) => ({
        title: `${hydrated?.names.get(item.actorId) ?? "?"} assigned you`,
      }),
    });
    const listed = await notifications
      .list({ include: ["actor"], locale: "en" })
      .orThrow();
    expect(hydrate).toHaveBeenCalledTimes(1);
    expect(hydrate.mock.calls[0]![1]).toEqual({ locale: "en" });
    expect(listed[0]).toMatchObject({
      text: { title: "Ada assigned you" },
      actor: { id: "u0", username: "ada", avatar: null },
    });
    expect(listed[2]!.actor).toBeNull();
    expect(listed[3]!.actor).toBeNull();
    expect(calls.map((call) => call.fn)).toEqual([
      "list_notifications",
      "notification_actors",
    ]);
    expect(calls[1]!.args).toEqual({ ids: ["u0", "gone"] });
  });

  it("resolves actor avatars stored as Storage object paths", async () => {
    const handlers = {
      list_notifications: () => [
        row(),
        row({ id: "r2", actor_id: "u1" }),
        row({ id: "r3", actor_id: "u2" }),
      ],
      notification_actors: () => ({
        u0: { username: "ada", avatar: null, avatarPath: "u0/face 1.webp" },
        u1: { username: "bob", avatarPath: null },
        u2: { username: "cy", avatarPath: "" },
      }),
    };
    const bucket = await createNotifications({
      transport: fakeTransport(handlers).transport,
      types,
      avatars: { url: "https://project.supabase.co/", bucket: "users" },
    })
      .list({ include: ["actor"] })
      .orThrow();
    expect(bucket.map((item) => item.actor)).toEqual([
      {
        id: "u0",
        username: "ada",
        avatar: null,
        avatarPath: "u0/face 1.webp",
        avatarUrl:
          "https://project.supabase.co/storage/v1/object/public/users/u0/face%201.webp",
      },
      { id: "u1", username: "bob", avatarPath: null },
      { id: "u2", username: "cy", avatarPath: "" },
    ]);
    const custom = await createNotifications({
      transport: fakeTransport(handlers).transport,
      types,
      avatars: (path) => `https://cdn.test/${path}`,
    })
      .list({ include: ["actor"] })
      .orThrow();
    expect(custom[0]!.actor?.avatarUrl).toBe("https://cdn.test/u0/face 1.webp");
    const plain = await createNotifications({
      transport: fakeTransport(handlers).transport,
      types,
    })
      .list({ include: ["actor"] })
      .orThrow();
    expect(plain[0]!.actor).not.toHaveProperty("avatarUrl");
  });

  it("skips the actor call without actors and maps its errors", async () => {
    const quiet = fakeTransport({
      list_notifications: () => [row({ actor_id: null })],
    });
    const plain = await createNotifications({
      transport: quiet.transport,
      types,
    })
      .list({ include: ["actor"] })
      .orThrow();
    expect(plain[0]!.actor).toBeNull();
    expect(quiet.calls).toHaveLength(1);
    const failing = fakeTransport({
      list_notifications: () => [row()],
      notification_actors: () => {
        throw Object.assign(new Error("missing"), { code: "42883" });
      },
    });
    expect(
      await createNotifications({ transport: failing.transport, types }).list({
        include: ["actor"],
      }),
    ).toMatchObject({ ok: false });
    const odd = fakeTransport({
      list_notifications: () => [row()],
      notification_actors: () => null,
    });
    expect(
      (
        await createNotifications({ transport: odd.transport, types })
          .list({ include: ["actor"] })
          .orThrow()
      )[0]!.actor,
    ).toBeNull();
    const thrown = fakeTransport({
      list_notifications: () => [row()],
      notification_actors: () => {
        throw new Error("boom");
      },
    });
    expect(
      await createNotifications({ transport: thrown.transport, types }).list({
        include: ["actor"],
      }),
    ).toMatchObject({ ok: false, error: { message: "boom" } });
  });

  it("counts, marks read, dismisses, resolves, subscribes and sets preferences", async () => {
    const { transport, calls } = fakeTransport({
      notification_counts: () => ({
        unread: 3,
        actionable: 4,
        actionable_subjects: 1,
      }),
      mark_notifications_read: () => ({
        count: 2,
        items: [row({ read_at: "2026-01-02T00:00:00Z" }), row({ id: "r2" })],
      }),
      dismiss_notifications: () => ({ count: 1, items: [row()] }),
      resolve_notifications: () => ({ count: 4, items: "not a list" }),
      purge_notifications: () => 12,
    });
    const notifications = createNotifications({
      transport,
      types,
      actionable: ["approval.requested"],
    });
    expect(
      await notifications.counts({ tenant: "organization_1" }),
    ).toMatchObject({
      ok: true,
      data: { unread: 3, actionable: 4, actionableSubjects: 1 },
    });
    const read = await notifications.markRead().orThrow();
    expect(read.count).toBe(2);
    expect(read.items.map((item) => item.id)).toEqual(["r1", "r2"]);
    expect(read.items[0]!.readAt?.toString()).toBe("2026-01-02T00:00:00Z");
    expect(await notifications.dismiss(["r1"])).toMatchObject({
      data: { count: 1, items: [{ id: "r1" }] },
    });
    expect(
      await notifications.resolve({
        type: "approval.requested",
        subject: { type: "invoice", id: "7" },
      }),
    ).toMatchObject({ data: { count: 4, items: [] } });
    expect(
      await notifications.subscribe({
        subject: { type: "task", id: "42" },
        level: "ignore",
        tenant: "organization_1",
      }),
    ).toMatchObject({ ok: true });
    expect(
      await notifications.setPreference({
        type: "*",
        channel: "email",
        enabled: false,
      }),
    ).toMatchObject({ ok: true });
    expect(await notifications.purge("30 days", 500)).toMatchObject({
      data: 12,
    });
    expect(calls.map((call) => [call.fn, call.args])).toEqual([
      [
        "notification_counts",
        { tenant: "organization_1", actionable: ["approval.requested"] },
      ],
      ["mark_notifications_read", { ids: null, tenant: null }],
      ["dismiss_notifications", { ids: ["r1"] }],
      [
        "resolve_notifications",
        {
          type: "approval.requested",
          subject_type: "invoice",
          subject_id: "7",
          tenant: null,
        },
      ],
      [
        "set_notification_subscription",
        {
          subject_type: "task",
          subject_id: "42",
          level: "ignore",
          tenant: "organization_1",
          member: null,
        },
      ],
      [
        "set_notification_preference",
        { type: "*", channel: "email", enabled: false, tenant: null },
      ],
      ["purge_notifications", { older_than: "30 days", batch: 500 }],
    ]);
  });

  it("reads missing counts as zero", async () => {
    const { transport } = fakeTransport();
    const notifications = createNotifications({ transport, types });
    expect(await notifications.counts()).toMatchObject({
      data: { unread: 0, actionable: 0, actionableSubjects: 0 },
    });
    expect(await notifications.list()).toMatchObject({ ok: true, data: [] });
  });
});

describe("createNotifications().deliver", () => {
  const claim = (deliveries: Record<string, unknown>[]) => {
    let served = false;
    return () => {
      if (served) return [];
      served = true;
      return deliveries;
    };
  };
  const delivery = (id: string, attempts = 1) => ({
    delivery_id: id,
    user_id: "u1",
    email: "u1@acme.test",
    attempts,
    notification: row(),
  });

  it("sends, skips and retries, completes each delivery and emits", async () => {
    const { transport, calls } = fakeTransport({
      claim_notification_deliveries: claim([
        delivery("d1"),
        delivery("d2"),
        delivery("d3"),
        delivery("d4", 5),
      ]),
    });
    const send = vi.fn<NotificationChannel["send"]>((message) => {
      switch (message.deliveryId) {
        case "d1":
          return { provider: "resend", providerMessageId: "m1" };
        case "d2":
          return { status: "skipped" };
        default:
          throw new Error("smtp down");
      }
    });
    const events = new EventHub();
    const seen: string[] = [];
    events.on("block", (event) => seen.push(event.type));
    const notifications = createNotifications({
      transport,
      types,
      events,
      render: (item) => ({ title: item.summary ?? "" }),
      channels: [{ apiVersion: 1, name: "email", send }],
    });
    const result = await notifications.deliver({ batch: 10, budgetMs: 10_000 });
    expect(result).toEqual({ sent: 1, skipped: 1, failed: 2 });
    expect(send.mock.calls[0]?.[0]).toMatchObject({
      channel: "email",
      email: "u1@acme.test",
      text: { title: "Assigned" },
      notification: { eventId: "e1", type: "task.assigned" },
    });
    const completions = calls
      .filter((call) => call.fn === "complete_notification_delivery")
      .map((call) => call.args);
    expect(completions).toEqual([
      {
        delivery: "d1",
        status: "sent",
        provider: "resend",
        provider_message_id: "m1",
      },
      {
        delivery: "d2",
        status: "skipped",
        provider: null,
        provider_message_id: null,
      },
      {
        delivery: "d3",
        status: "pending",
        error: "smtp down",
        max_attempts: 5,
      },
      {
        delivery: "d4",
        status: "pending",
        error: "smtp down",
        max_attempts: 5,
      },
    ]);
    expect(seen).toEqual([
      "notification.delivered",
      "notification.failed",
      "notification.failed",
    ]);
  });

  it("only works on the requested channels and claims again while batches are full", async () => {
    let claims = 0;
    const { transport, calls } = fakeTransport({
      claim_notification_deliveries: () => {
        claims += 1;
        return claims === 1 ? [delivery("d1")] : [];
      },
    });
    const email = { apiVersion: 1 as const, name: "email", send: vi.fn() };
    const push = { apiVersion: 1 as const, name: "push", send: vi.fn() };
    const notifications = createNotifications({
      transport,
      types,
      channels: [email, push],
    });
    expect(
      await notifications.deliver({ channels: ["email"], batch: 1 }),
    ).toEqual({ sent: 1, skipped: 0, failed: 0 });
    expect(push.send).not.toHaveBeenCalled();
    expect(
      calls.filter((call) => call.fn === "claim_notification_deliveries"),
    ).toHaveLength(2);
  });

  it("throws on a claim without a notification", async () => {
    const { transport } = fakeTransport({
      claim_notification_deliveries: claim([{ delivery_id: "d1" }]),
    });
    const notifications = createNotifications({
      transport,
      types,
      channels: [{ apiVersion: 1, name: "email", send: vi.fn() }],
    });
    await expect(notifications.deliver()).rejects.toThrow(/no notification/);
  });
});

describe("testNotificationChannel", () => {
  it("passes a conforming channel and checks delivery", async () => {
    const received: string[] = [];
    const report = await testNotificationChannel(
      {
        apiVersion: 1,
        name: "email",
        send: (message) => {
          received.push(message.deliveryId);
          return { status: "sent", provider: "test" };
        },
      },
      { email: "a@b.test", received: async () => received },
    );
    expect(report.checks.every((check) => check.ok)).toBe(true);
  });

  it("lists every broken rule", async () => {
    await expect(
      testNotificationChannel(
        {
          // @ts-expect-error -- a channel from a future contract
          apiVersion: 2,
          name: "",
          // @ts-expect-error -- not a valid status
          send: () => ({ status: "queued", provider: 1 }),
        },
        { received: async () => [] },
      ),
    ).rejects.toThrow(/failed 4 of 4/);
  });
});

describe("typed notification data and hooks", () => {
  const typed = {
    "invoice.paid": v.object({
      amount: v.number(),
      paidAt: v.pipe(
        v.string(),
        v.isoTimestamp(),
        v.transform((value) => new Date(value)),
      ),
    }),
  };

  it("parses stored data with its type's schema on reads", async () => {
    const { transport } = fakeTransport({
      list_notifications: () => [
        row({
          type: "invoice.paid",
          data: { amount: 10, paidAt: "2026-01-01T00:00:00Z" },
        }),
        row({ id: "r2", type: "retired.type", data: { anything: true } }),
      ],
    });
    const notifications = createNotifications({ transport, types: typed });
    const [paid, retired] = await notifications.list().orThrow();
    expect(paid).toMatchObject({
      type: "invoice.paid",
      data: { amount: 10, paidAt: expect.any(Date) },
    });
    expect(retired?.data).toEqual({ anything: true });
  });

  it("returns NOTIFICATION_DATA_INVALID for stored data the schema rejects", async () => {
    const { transport } = fakeTransport({
      get_notification: () => row({ type: "invoice.paid", data: {} }),
    });
    const notifications = createNotifications({ transport, types: typed });
    expect(await notifications.get("r1")).toMatchObject({
      ok: false,
      error: { kind: "validation", hint: "NOTIFICATION_DATA_INVALID" },
    });
  });

  it("runs hooks on send, including sends from the sink", async () => {
    const { transport, calls } = fakeTransport({
      send_notification: () => ({ id: "e1", recipients: ["u1"] }),
    });
    const before = vi.fn(
      ([, input]: readonly [string, { readonly tenant?: string }]) =>
        input.tenant === "frozen"
          ? dbError("forbidden", "This organization is frozen")
          : undefined,
    );
    const notifications = createNotifications({
      transport,
      types,
      hooks: { send: { before } },
    });
    expect(
      await notifications.send("task.assigned", {
        tenant: "frozen",
        data: { title: "x" },
      }),
    ).toMatchObject({ ok: false, error: { kind: "forbidden" } });
    expect(calls).toEqual([]);
    await notifications
      .sink({
        map: () => ({
          type: "task.assigned",
          recipients: ["u1"],
          tenant: "organization_1",
          data: { title: "From an event" },
        }),
      })
      .send([
        {
          specversion: "1.0",
          id: "evt",
          source: "test",
          type: "dev.better-supabase.thing",
        },
      ]);
    expect(before).toHaveBeenCalledTimes(2);
    expect(calls.map((call) => call.fn)).toEqual(["send_notification"]);
  });
});

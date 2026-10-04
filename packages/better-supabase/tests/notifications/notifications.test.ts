import type { StandardSchemaV1 } from "@standard-schema/spec";

import { describe, expect, it, vi } from "vitest";

import type { KitTransport } from "../../src/core/kit-transport.ts";
import type { NotificationChannel } from "../../src/notifications/index.ts";

import { EventHub } from "../../src/core/events.ts";
import { createNotifications } from "../../src/notifications/index.ts";
import { testNotificationChannel } from "../../src/testing/index.ts";

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

const kinds = { "task.assigned": titled, "approval.requested": titled };

type Handler = (args: Readonly<Record<string, unknown>>) => unknown;

function fakeTransport(handlers: Record<string, Handler> = {}) {
  const calls: { schema: string; fn: string; args: Record<string, unknown> }[] =
    [];
  const transport: KitTransport = {
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
  kind: "task.assigned",
  data: { title: "Ship it" },
  tenant: "org_1",
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

describe("createNotifications().send", () => {
  it("validates the data, calls notify, emits and runs onSent", async () => {
    const { transport, calls } = fakeTransport({ notify: () => "e1" });
    const events = new EventHub();
    const seen: string[] = [];
    events.on("kit", (event) => seen.push(event.type));
    const onSent = vi.fn();
    const notifications = createNotifications({
      transport,
      kinds,
      schema: "app",
      events,
      onSent,
    });
    const sent = await notifications.send("task.assigned", {
      recipients: ["u1"],
      tenant: "org_1",
      subject: { type: "task", id: "42", label: "Ship it" },
      data: { title: "Ship it" },
      key: "task-42",
    });
    expect(sent).toMatchObject({ ok: true, data: "e1" });
    expect(calls[0]).toMatchObject({
      schema: "app",
      fn: "notify",
      args: {
        notification: {
          kind: "task.assigned",
          recipients: ["u1"],
          tenant: "org_1",
          subject_type: "task",
          subject_id: "42",
          subject_label: "Ship it",
          key: "task-42",
          data: { title: "Ship it" },
        },
      },
    });
    expect(seen).toEqual(["notification.created"]);
    expect(onSent).toHaveBeenCalledWith({
      id: "e1",
      kind: "task.assigned",
      tenant: "org_1",
      recipients: ["u1"],
    });
  });

  it("rejects unknown kinds and invalid data without calling the database", async () => {
    const { transport, calls } = fakeTransport();
    const notifications = createNotifications({ transport, kinds });
    const unknown = await notifications.send(
      // @ts-expect-error -- not a configured kind
      "nope",
      { data: {} },
    );
    expect(unknown).toMatchObject({
      ok: false,
      error: { kind: "validation", hint: "NOTIFICATION_KIND_UNKNOWN" },
    });
    const invalid = await notifications.send("task.assigned", {
      // @ts-expect-error -- title is required
      data: {},
    });
    expect(invalid).toMatchObject({ ok: false, error: { kind: "validation" } });
    expect(calls).toHaveLength(0);
  });

  it("returns null without events when nobody is left to notify", async () => {
    const { transport } = fakeTransport({ notify: () => null });
    const onSent = vi.fn();
    const notifications = createNotifications({ transport, kinds, onSent });
    const sent = await notifications.send("task.assigned", {
      data: { title: "x" },
    });
    expect(sent).toMatchObject({ ok: true, data: null });
    expect(onSent).not.toHaveBeenCalled();
  });

  it("maps database errors through the error mappers and onSent failures", async () => {
    const { transport } = fakeTransport({
      notify: () => {
        throw Object.assign(new Error("not allowed"), {
          code: "42501",
          hint: "NOTIFICATION_FORBIDDEN",
        });
      },
    });
    const notifications = createNotifications({ transport, kinds });
    const denied = await notifications.send("task.assigned", {
      data: { title: "x" },
    });
    expect(denied).toMatchObject({
      ok: false,
      error: { kind: "forbidden", hint: "NOTIFICATION_FORBIDDEN" },
    });

    const failing = createNotifications({
      transport: fakeTransport({ notify: () => "e1" }).transport,
      kinds,
      onSent: () => {
        throw new Error("cache down");
      },
    });
    const sent = await failing.send("task.assigned", { data: { title: "x" } });
    expect(sent.ok).toBe(false);
  });
});

describe("createNotifications reads and writes", () => {
  it("lists rendered items and passes the filters", async () => {
    const { transport, calls } = fakeTransport({
      list_notifications: () => [row(), row({ id: "r2", subject_type: null })],
    });
    const notifications = createNotifications({
      transport,
      kinds,
      render: (item, { locale }) => ({
        title: `${locale ?? "en"}: ${item.summary ?? ""}`,
      }),
    });
    const listed = await notifications.list({
      status: "unread",
      kinds: ["task.assigned"],
      before: Temporal.Instant.from("2026-02-01T00:00:00Z"),
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
      kinds: ["task.assigned"],
      before: "2026-02-01T00:00:00Z",
      before_id: null,
      max_items: 10,
    });
    await notifications.list({ before: first! });
    expect(calls[1]?.args).toMatchObject({
      before: "2026-01-01T00:00:00Z",
      before_id: "r1",
    });
  });

  it("counts, marks read, dismisses, resolves, subscribes and sets preferences", async () => {
    const { transport, calls } = fakeTransport({
      notification_counts: () => ({ unread: 3, actionable: 1 }),
      mark_notifications_read: () => 2,
      dismiss_notifications: () => 1,
      resolve_notifications: () => 4,
      purge_notifications: () => 12,
    });
    const notifications = createNotifications({
      transport,
      kinds,
      actionable: ["approval.requested"],
    });
    expect(await notifications.counts({ tenant: "org_1" })).toMatchObject({
      ok: true,
      data: { unread: 3, actionable: 1 },
    });
    expect(await notifications.markRead()).toMatchObject({ data: 2 });
    expect(await notifications.dismiss(["r1"])).toMatchObject({ data: 1 });
    expect(
      await notifications.resolve({
        kind: "approval.requested",
        subject: { type: "invoice", id: "7" },
      }),
    ).toMatchObject({ data: 4 });
    expect(
      await notifications.subscribe({
        subject: { type: "task", id: "42" },
        level: "ignore",
        tenant: "org_1",
      }),
    ).toMatchObject({ ok: true });
    expect(
      await notifications.setPreference({
        kind: "*",
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
        { tenant: "org_1", actionable: ["approval.requested"] },
      ],
      ["mark_notifications_read", { ids: null, tenant: null }],
      ["dismiss_notifications", { ids: ["r1"] }],
      [
        "resolve_notifications",
        {
          kind: "approval.requested",
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
          tenant: "org_1",
          member: null,
        },
      ],
      [
        "set_notification_preference",
        { kind: "*", channel: "email", enabled: false, tenant: null },
      ],
      ["purge_notifications", { older_than: "30 days", batch: 500 }],
    ]);
  });

  it("reads missing counts as zero", async () => {
    const { transport } = fakeTransport();
    const notifications = createNotifications({ transport, kinds });
    expect(await notifications.counts()).toMatchObject({
      data: { unread: 0, actionable: 0 },
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
    events.on("kit", (event) => seen.push(event.type));
    const notifications = createNotifications({
      transport,
      kinds,
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
      notification: { eventId: "e1", kind: "task.assigned" },
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
      kinds,
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
      kinds,
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

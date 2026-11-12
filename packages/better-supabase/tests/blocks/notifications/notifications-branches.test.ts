import type { StandardSchemaV1 } from "@standard-schema/spec";

import * as v from "valibot";
import { describe, expect, it, vi } from "vitest";

import type { NotificationChannel } from "../../../src/blocks/notifications/index.ts";
import type { BlockTransport } from "../../../src/core/block-transport.ts";

import { createNotifications } from "../../../src/blocks/notifications/index.ts";

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

const types = { "task.assigned": titled };

type Handler = (args: Readonly<Record<string, unknown>>) => unknown;

function fakeTransport(handlers: Record<string, Handler> = {}) {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];

  const transport: BlockTransport = {
    async call(_schema, fn, args) {
      calls.push({ fn, args: { ...args } });
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

describe("notification rows and defaults", () => {
  it("reads a delivery event whose detail is not an object", async () => {
    const { transport } = fakeTransport({
      list_subject_deliveries: () => [
        {
          id: "d1",
          events: [{ kind: "delivered", occurred_at: null, detail: "text" }],
        },
      ],
    });

    const notifications = createNotifications({ transport, types });

    const result = await notifications
      .subjectDeliveries({ subject: { type: "task", id: "42" } })
      .orThrow();

    expect(result[0]?.events[0]).toMatchObject({
      kind: "delivered",
      detail: {},
    });
  });

  it("reads an update that is not an object as zero and passes defaults", async () => {
    const { transport, calls } = fakeTransport({
      list_notifications: () => null,
      notification_counts: () => null,
      get_notification: () => null,
    });

    const notifications = createNotifications({ transport, types });

    expect(await notifications.markUnread({ ids: ["r1"] }).orThrow()).toEqual({
      count: 0,
      items: [],
    });
    expect(await notifications.counts().orThrow()).toEqual({
      unread: 0,
      actionable: 0,
      actionableSubjects: 0,
    });
    expect(await notifications.get({ id: "r1" }).orThrow()).toBeNull();
    expect(calls.find((c) => c.fn === "notification_counts")?.args).toEqual({
      tenant: null,
      actionable: [],
    });
    expect(
      calls.find((c) => c.fn === "mark_notifications_unread")?.args,
    ).toEqual({ ids: ["r1"], tenant: null });
  });

  it("resolves with a resolution and subscribes with a member", async () => {
    const { transport, calls } = fakeTransport({
      resolve_notifications: () => ({ count: 2, items: [] }),
    });

    const notifications = createNotifications({ transport, types });

    const resolved = await notifications
      .resolve({
        type: "task.assigned",
        subject: { type: "task", id: "42" },
        resolution: { status: "done" },
      })
      .orThrow();

    await notifications
      .resolve({ type: "task.assigned", subject: { type: "task", id: "42" } })
      .orThrow();
    expect(resolved.count).toBe(2);
    expect(calls[0]?.args["resolution"]).toEqual({ status: "done" });
    expect(calls[1]?.args).not.toHaveProperty("resolution");

    await notifications
      .subscribe({
        subject: { type: "task", id: "42" },
        level: "all",
        userId: "u2",
        ifAbsent: true,
        tenant: "t1",
      })
      .orThrow();
    expect(calls[2]?.args).toMatchObject({
      member: "u2",
      if_absent: true,
      tenant: "t1",
    });
  });

  it("passes suppression, purge, delivery listing and preference defaults", async () => {
    const { transport, calls } = fakeTransport({
      list_notification_suppressions: () => [
        { channel: "email", address: "a@b.test", reason: "bounce" },
        { channel: "email", address: "c@d.test", reason: "nonsense" },
      ],
      list_notification_preferences: () => null,
      list_notification_subscriptions: () => null,
    });

    const notifications = createNotifications({ transport, types });

    await notifications.suppress({ address: "a@b.test", reason: "bounce" });
    await notifications.unsuppress({ address: "a@b.test" });
    await notifications.purge();
    await notifications.subjectDeliveries({ subject: { type: "t", id: "1" } });
    expect(await notifications.preferences().orThrow()).toEqual([]);
    expect(await notifications.subscriptions().orThrow()).toEqual([]);

    const listed = await notifications.suppressions().orThrow();

    expect(listed).toHaveLength(1);
    expect(calls.map((c) => c.args)).toEqual(
      expect.arrayContaining([
        expect.objectContaining({ channel: "email", provider: null }),
        { address: "a@b.test", channel: "email" },
        { older_than: null, batch: null },
        expect.objectContaining({ max_items: 50, tenant: null }),
      ]),
    );
  });

  it("records a provider event without an id, time or detail", async () => {
    const { transport, calls } = fakeTransport({
      record_delivery_event: () => null,
    });

    const notifications = createNotifications({ transport, types });

    await notifications
      .recordDeliveryEvent({
        provider: "resend",
        providerMessageId: "m1",
        kind: "delivered",
      })
      .orThrow();
    expect(calls[0]?.args).toMatchObject({
      provider_event_id: null,
      occurred_at: null,
      detail: {},
      suppress: null,
    });
  });
});

describe("notification fields", () => {
  const fields = v.object({ tag: v.string() });

  it("rejects stored fields the schema refuses, for known and unknown types", async () => {
    const { transport } = fakeTransport({
      get_notification: (args) =>
        args["id"] === "known"
          ? row({ fields: { tag: 1 } })
          : row({ type: "other", fields: { tag: 1 } }),
    });

    const notifications = createNotifications({ transport, types, fields });

    const known = await notifications.get({ id: "known" });
    const unknown = await notifications.get({ id: "unknown" });

    expect(known.ok).toBe(false);
    expect(unknown.ok).toBe(false);
  });

  it("reads fields of an unknown type and sends without fields", async () => {
    const { transport, calls } = fakeTransport({
      get_notification: () => row({ type: "other", fields: { tag: "x" } }),
      send_notification: () => null,
    });

    const notifications = createNotifications({ transport, types, fields });

    const item = await notifications.get({ id: "r1" }).orThrow();

    expect(item?.fields).toEqual({ tag: "x" });

    await notifications
      .send({
        type: "task.assigned",
        input: {
          data: { title: "Hi" },
          recipients: ["u1"],
          fields: { tag: "y" },
        },
      })
      .orThrow();
    expect(calls.at(-1)?.args["notification"]).toMatchObject({
      fields: { tag: "y" },
    });
  });

  it("refuses fields the schema rejects on send", async () => {
    const { transport } = fakeTransport();
    const notifications = createNotifications({ transport, types, fields });

    const result = await notifications.send({
      type: "task.assigned",
      input: {
        data: { title: "Hi" },
        recipients: ["u1"],
        // SAFETY: deliberately invalid fields to exercise the schema refusal.
        fields: { tag: 5 } as unknown as { tag: string },
      },
    });

    expect(result.ok).toBe(false);
  });
});

describe("notification batches and contacts", () => {
  it("sends nothing when every item is invalid and skips missing results", async () => {
    const { transport, calls } = fakeTransport({
      send_notifications: () => [
        { notification: { id: "e1", recipients: [] } },
      ],
    });

    const notifications = createNotifications({ transport, types });

    // SAFETY: an unknown type and empty data are the invalid item under test.
    const invalid = [{ type: "nope", data: {} }] as unknown as Parameters<
      typeof notifications.sendMany
    >[0];

    const none = await notifications.sendMany(invalid).orThrow();

    expect(none[0]?.ok).toBe(false);
    expect(calls).toHaveLength(0);

    const short = await notifications
      .sendMany([
        { type: "task.assigned", data: { title: "a" }, recipients: ["u1"] },
        { type: "task.assigned", data: { title: "b" }, recipients: ["u1"] },
      ])
      .orThrow();

    expect(short).toHaveLength(2);
    expect(short[1]?.ok).toBe(false);
  });

  it("emails contacts under a fresh id when there is no key", async () => {
    const sent: unknown[] = [];

    const notifications = createNotifications({
      transport: fakeTransport({ send_notification: () => null }).transport,
      types,
      render: () => ({ title: "Hello" }),
      email: {
        from: "hi@acme.test",
        transport: {
          apiVersion: 1,
          channel: "email",
          provider: "fake",
          send: async (message) => {
            sent.push(message);

            return { providerMessageId: "m1" };
          },
        },
      },
    });

    const result = await notifications
      .send({
        type: "task.assigned",
        input: {
          data: { title: "Hi" },
          recipients: [{ email: "cara@client.test" }],
        },
      })
      .orThrow();

    expect(result?.eventId).toMatch(/^[\da-f-]{36}$/);
    expect(sent).toHaveLength(1);
  });
});

describe("notification delivery rendering", () => {
  const delivery = (id: string, extra: Record<string, unknown> = {}) => ({
    delivery_id: id,
    user_id: "u1",
    email: "u1@acme.test",
    notification: row(),
    ...extra,
  });

  const once = (rows: Record<string, unknown>[]) => {
    let served = false;

    return () => {
      if (served) {
        return [];
      }

      served = true;

      return rows;
    };
  };

  it("defaults attempts, renders without a locale and uses default options", async () => {
    const { transport, calls } = fakeTransport({
      claim_notification_deliveries: once([delivery("d1")]),
    });

    const send = vi.fn<NotificationChannel["send"]>(() => undefined);

    const notifications = createNotifications({
      transport,
      types,
      channels: [{ apiVersion: 1, name: "email", send }],
    });

    expect(await notifications.deliver()).toEqual({
      sent: 1,
      skipped: 0,
      failed: 0,
    });
    expect(send.mock.calls[0]?.[0]).toMatchObject({ attempts: 1 });
    expect(send.mock.calls[0]?.[0]).not.toHaveProperty("text");
    expect(send.mock.calls[0]?.[0]).not.toHaveProperty("hydrated");
    expect(calls[0]?.args).toMatchObject({ lease: "5 minutes", max_items: 50 });
  });

  it("hydrates per locale and hands the hydration to render and send", async () => {
    const { transport } = fakeTransport({
      claim_notification_deliveries: once([
        delivery("d1", { locale: "nl" }),
        delivery("d2"),
      ]),
    });

    const hydrate = vi.fn(async (_items: unknown, context: object) => ({
      context,
    }));

    const send = vi.fn<NotificationChannel["send"]>(() => ({ status: "sent" }));

    const notifications = createNotifications({
      transport,
      types,
      hydrate,
      render: (item, context) => ({
        title: `${item.summary ?? ""}:${context.locale ?? "none"}`,
      }),
      channels: [{ apiVersion: 1, name: "email", send }],
    });

    await notifications.deliver({ maxAttempts: 2, lease: "1 minute" });

    const contexts = hydrate.mock.calls.map((call) => call[1]);

    expect(contexts).toEqual(expect.arrayContaining([{ locale: "nl" }, {}]));

    const first = send.mock.calls.find((c) => c[0].locale === "nl")?.[0];

    expect(first).toMatchObject({
      text: { title: "Assigned:nl" },
      hydrated: { context: { locale: "nl" } },
    });
  });

  it("sends nothing and retries when hydration throws", async () => {
    const { transport, calls } = fakeTransport({
      claim_notification_deliveries: once([delivery("d1")]),
    });

    const send = vi.fn<NotificationChannel["send"]>(() => undefined);

    const notifications = createNotifications({
      transport,
      types,
      hydrate: async () => {
        throw new Error("profiles down");
      },
      channels: [{ apiVersion: 1, name: "email", send }],
    });

    expect(await notifications.deliver()).toEqual({
      sent: 0,
      skipped: 0,
      failed: 1,
    });
    expect(send).not.toHaveBeenCalled();
    expect(calls.at(-1)?.args).toMatchObject({ error: "profiles down" });
  });

  it("renders with an undefined hydration", async () => {
    const { transport } = fakeTransport({
      claim_notification_deliveries: once([delivery("d1")]),
    });

    const send = vi.fn<NotificationChannel["send"]>(() => undefined);

    const notifications = createNotifications({
      transport,
      types,
      hydrate: async () => undefined,
      render: () => ({ title: "t" }),
      channels: [{ apiVersion: 1, name: "email", send }],
    });

    await notifications.deliver();
    expect(send.mock.calls[0]?.[0]).not.toHaveProperty("hydrated");
    expect(send.mock.calls[0]?.[0]).toMatchObject({ text: { title: "t" } });
  });
});

describe("notification sparse answers", () => {
  it("reads objects without counts or items as zero", async () => {
    const { transport } = fakeTransport({
      dismiss_notifications: () => ({}),
      notification_counts: () => ({}),
      notification_page: () => null,
      list_notification_suppressions: () => null,
    });

    const notifications = createNotifications({ transport, types });

    expect(await notifications.dismiss(["r1"]).orThrow()).toEqual({
      count: 0,
      items: [],
    });
    expect(await notifications.counts().orThrow()).toEqual({
      unread: 0,
      actionable: 0,
      actionableSubjects: 0,
    });
    expect(await notifications.page().orThrow()).toEqual({
      items: [],
      total: 0,
      totalCapped: false,
      hasMore: false,
      limit: 0,
    });
    expect(await notifications.suppressions({ limit: 5 }).orThrow()).toEqual(
      [],
    );
  });

  it("subscribes the caller and records an event under the default id", async () => {
    const { transport, calls } = fakeTransport({
      record_delivery_event: () => ({
        id: "x",
        delivery_id: "d1",
        kind: "delivered",
        created: true,
      }),
    });

    const notifications = createNotifications({ transport, types });

    await notifications
      .subscribe({ subject: { type: "task", id: "1" }, level: "all" })
      .orThrow();
    expect(calls[0]?.args).toMatchObject({ member: null });

    await notifications
      .recordDeliveryEvent({
        provider: "resend",
        providerMessageId: "m1",
        kind: "delivered",
      })
      .orThrow();
    expect(calls[1]?.args["provider_event_id"]).toBeNull();
  });

  it("refuses an empty tenant for a permission audience", async () => {
    const { transport } = fakeTransport();
    const notifications = createNotifications({ transport, types });

    const result = await notifications.send({
      type: "task.assigned",
      input: { data: { title: "Hi" }, permission: "x.read", tenant: "" },
    });

    expect(!result.ok && result.error.hint).toBe(
      "NOTIFICATION_PERMISSION_NEEDS_TENANT",
    );
  });
});

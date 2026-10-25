import type { StandardSchemaV1 } from "@standard-schema/spec";

import { describe, expect, it, vi } from "vitest";

import type {
  DeliveryTransport,
  EmailMessage,
  MailCategory,
  NotificationMessage,
} from "../../../src/blocks/notifications/index.ts";
import type { BlockTransport } from "../../../src/core/block-transport.ts";
import type { SubscriberPolicy } from "../../../src/core/contracts/authorization-hooks.ts";

import {
  createNotifications,
  emailChannel,
  mailHeaders,
} from "../../../src/blocks/notifications/index.ts";
import { defineAuthorizationHooks } from "../../../src/core/contracts/authorization-hooks.ts";
import { DbException, dbError } from "../../../src/core/errors.ts";
import { EventHub } from "../../../src/core/events.ts";

const titled: StandardSchemaV1<{ title: string }> = {
  "~standard": {
    version: 1,
    vendor: "test",
    validate: (value) => ({ value: value as { title: string } }),
  },
};

const types = { "task.assigned": titled, "security.signin": titled };

type Handler = (args: Readonly<Record<string, unknown>>) => unknown;

function fakeTransport(handlers: Record<string, Handler> = {}) {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];

  const transport: BlockTransport = {
    async call(_schema, fn, args) {
      calls.push({ fn, args: { ...args } });

      return handlers[fn]?.(args) ?? null;
    },
  };

  const completions = () =>
    calls
      .filter((call) => call.fn === "complete_notification_delivery")
      .map((call) => call.args);

  return { transport, calls, completions };
}

function recordingTransport() {
  const sent: { message: EmailMessage; idempotencyKey: string }[] = [];

  const transport: DeliveryTransport = {
    apiVersion: 1,
    channel: "email",
    provider: "fake",
    send(message, { idempotencyKey }) {
      sent.push({ message, idempotencyKey });

      return { providerMessageId: `m-${idempotencyKey}` };
    },
  };

  return { transport, sent };
}

const notification = (overrides: Record<string, unknown> = {}) => ({
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

const delivery = (
  id: string,
  user: string,
  extra: Record<string, unknown> = {},
) => ({
  delivery_id: id,
  user_id: user,
  email: `${user}@acme.test`,
  attempts: 1,
  notification: notification(),
  ...extra,
});

const claimOnce = (rows: Record<string, unknown>[]) => {
  let served = false;

  return () => {
    if (served) {
      return [];
    }

    served = true;

    return rows;
  };
};

const message = (
  overrides: Partial<NotificationMessage> = {},
): NotificationMessage => ({
  deliveryId: "d1",
  channel: "email",
  attempts: 1,
  userId: "u1",
  email: "u1@acme.test",
  locale: null,
  notification: {
    id: "r1",
    eventId: "e1",
    type: "task.assigned",
    data: { title: "Ship it" },
    tenant: null,
    actorId: null,
    subject: null,
    summary: null,
    actionPath: null,
    priority: null,
    createdAt: Temporal.Instant.fromEpochMilliseconds(0),
    readAt: null,
    resolvedAt: null,
    resolution: null,
    actions: [],
    fields: {},
  },
  text: { title: "Assigned", body: "You have a task" },
  ...overrides,
});

describe("mailHeaders", () => {
  const unsubscribe = {
    url: "https://app.test/unsubscribe?t=abc",
    mailto: "mailto:unsubscribe@app.test?subject=stop",
  };

  it("marks every category auto-generated (RFC 3834)", () => {
    for (const category of ["notification", "security", "approval"] as const) {
      expect(mailHeaders(category)["Auto-Submitted"]).toBe("auto-generated");
    }
  });

  it("gives notification mail List-Unsubscribe and one-click (RFC 2369, RFC 8058)", () => {
    expect(mailHeaders("notification", unsubscribe)).toEqual({
      "Auto-Submitted": "auto-generated",
      "List-Unsubscribe":
        "<https://app.test/unsubscribe?t=abc>, <mailto:unsubscribe@app.test?subject=stop>",
      "List-Unsubscribe-Post": "List-Unsubscribe=One-Click",
    });
  });

  it.each(["security", "approval"] as const)(
    "never gives %s mail an unsubscribe header",
    (category: MailCategory) => {
      expect(mailHeaders(category, unsubscribe)).toEqual({
        "Auto-Submitted": "auto-generated",
      });
    },
  );

  it("leaves out one-click for a mailto-only target and both for an empty one", () => {
    expect(
      mailHeaders("notification", { mailto: "mailto:u@app.test" }),
    ).toEqual({
      "Auto-Submitted": "auto-generated",
      "List-Unsubscribe": "<mailto:u@app.test>",
    });
    expect(mailHeaders("notification", {})).toEqual({
      "Auto-Submitted": "auto-generated",
    });
  });

  it("refuses a URL that is not https and an address that is not mailto", () => {
    expect(() =>
      mailHeaders("notification", { url: "http://app.test/u" }),
    ).toThrow(/https/);
    expect(() => mailHeaders("notification", { url: "not a url" })).toThrow(
      /not a URL/,
    );
    expect(() => mailHeaders("notification", { mailto: "u@app.test" })).toThrow(
      /mailto/,
    );
  });
});

describe("emailChannel", () => {
  it("sends with the delivery id as the idempotency key and returns the provider id", async () => {
    const { transport, sent } = recordingTransport();

    const channel = emailChannel({
      transport,
      from: "Acme <hi@acme.test>",
      replyTo: "support@acme.test",
      unsubscribe: () => ({ url: "https://acme.test/u" }),
    });

    expect(channel).toMatchObject({ apiVersion: 1, name: "email" });
    const result = await channel.send(message({ deliveryId: "d-42" }));
    expect(result).toEqual({ provider: "fake", providerMessageId: "m-d-42" });
    expect(sent).toEqual([
      {
        idempotencyKey: "d-42",
        message: {
          from: "Acme <hi@acme.test>",
          to: "u1@acme.test",
          subject: "Assigned",
          text: "You have a task",
          replyTo: "support@acme.test",
          category: "notification",
          headers: {
            "Auto-Submitted": "auto-generated",
            "List-Unsubscribe": "<https://acme.test/u>",
            "List-Unsubscribe-Post": "List-Unsubscribe=One-Click",
          },
        },
      },
    ]);
  });

  it.each(["security", "approval"] as const)(
    "sends %s mail without unsubscribe headers and never asks for a target",
    async (category) => {
      const { transport, sent } = recordingTransport();
      const unsubscribe = vi.fn(() => ({ url: "https://acme.test/u" }));

      const channel = emailChannel({
        transport,
        from: "hi@acme.test",
        compose: () => ({ subject: "Code", html: "<p>123</p>", category }),
        unsubscribe,
      });

      await channel.send(message());
      expect(unsubscribe).not.toHaveBeenCalled();
      expect(sent[0]?.message).toEqual({
        from: "hi@acme.test",
        to: "u1@acme.test",
        subject: "Code",
        html: "<p>123</p>",
        category,
        headers: { "Auto-Submitted": "auto-generated" },
      });
    },
  );

  it("skips a recipient without an address and needs render or compose", async () => {
    const { transport, sent } = recordingTransport();
    const channel = emailChannel({ transport, from: "hi@acme.test" });
    expect(await channel.send(message({ email: null }))).toEqual({
      status: "skipped",
      provider: "fake",
    });
    const { text: _text, ...bare } = message();
    await expect(channel.send(bare)).rejects.toThrow(/render/);
    expect(await channel.send(message({ text: { title: "Hi" } }))).toEqual({
      provider: "fake",
      providerMessageId: "m-d1",
    });
    expect(sent[0]?.message.text).toBe("Hi");
  });

  it("refuses a transport for another channel or API version", () => {
    const { transport } = recordingTransport();
    expect(() =>
      emailChannel({
        // @ts-expect-error -- a transport from a future contract
        transport: { ...transport, apiVersion: 2 },
        from: "hi@acme.test",
      }),
    ).toThrow(/apiVersion 1/);
  });
});

describe("createNotifications({ email }).deliver", () => {
  it("honours suppressions: skips the address, records why and never sends", async () => {
    const { transport: mail, sent } = recordingTransport();

    const { transport, completions } = fakeTransport({
      claim_notification_deliveries: claimOnce([
        delivery("d1", "u1", { suppressed: "bounce" }),
        delivery("d2", "u2", { suppressed: null }),
      ]),
    });

    const notifications = createNotifications({
      transport,
      types,
      render: (item) => ({ title: item.summary ?? "" }),
      email: { transport: mail, from: "hi@acme.test" },
    });

    expect(await notifications.deliver()).toEqual({
      sent: 1,
      skipped: 1,
      failed: 0,
    });
    expect(sent.map((entry) => entry.message.to)).toEqual(["u2@acme.test"]);
    expect(sent[0]?.idempotencyKey).toBe("d2");
    expect(completions()).toEqual([
      { delivery: "d1", status: "skipped", error: "suppressed: bounce" },
      {
        delivery: "d2",
        status: "sent",
        provider: "fake",
        provider_message_id: "m-d2",
      },
    ]);
  });

  it("checks recipients through audience before sending, once per notification", async () => {
    const { transport: mail, sent } = recordingTransport();

    const { transport, completions } = fakeTransport({
      claim_notification_deliveries: claimOnce([
        delivery("d1", "u1"),
        delivery("d2", "u2"),
        delivery("d3", "u3", { suppressed: "complaint" }),
        delivery("d4", "u4", {
          notification: notification({ id: "r9", event_id: "e2" }),
        }),
      ]),
    });

    const audience = vi.fn<SubscriberPolicy>((_event, subscribers) =>
      subscribers.filter((subscriber) => subscriber.principal !== "u2"),
    );

    const notifications = createNotifications({
      transport,
      types,
      render: (item) => ({ title: item.summary ?? "" }),
      email: { transport: mail, from: "hi@acme.test" },
      audience: audience as unknown as SubscriberPolicy,
    });

    expect(await notifications.deliver()).toEqual({
      sent: 2,
      skipped: 2,
      failed: 0,
    });
    expect(audience).toHaveBeenCalledTimes(2);
    expect(audience.mock.calls[0]?.[0]).toEqual({
      type: "task.assigned",
      tenant: "organization_1",
      actorId: "u0",
      payload: { title: "Ship it" },
      subject: "task/42",
    });
    expect(
      audience.mock.calls[0]?.[1].map((subscriber) => subscriber.principal),
    ).toEqual(["u1", "u2"]);
    expect(sent.map((entry) => entry.message.to)).toEqual([
      "u1@acme.test",
      "u4@acme.test",
    ]);
    expect(completions()).toContainEqual({
      delivery: "d2",
      status: "skipped",
      error: "audience",
    });
  });

  it("falls back to the server's delivery audience and never widens a fan-out", async () => {
    const { transport: mail, sent } = recordingTransport();

    const { transport } = fakeTransport({
      claim_notification_deliveries: claimOnce([delivery("d1", "u1")]),
    });

    const notifications = createNotifications({
      transport,
      types,
      render: (item) => ({ title: item.summary ?? "" }),
      email: { transport: mail, from: "hi@acme.test" },
      server: {
        authorization: defineAuthorizationHooks({
          apiVersion: 1,
          name: "test",
          delivery: {
            // A leaky policy that names someone new.
            audience: (() => [
              { principal: "intruder" },
              { principal: "u1", kind: "user" },
            ]) as unknown as SubscriberPolicy,
          },
        }),
      },
    });

    expect(await notifications.deliver()).toEqual({
      sent: 1,
      skipped: 0,
      failed: 0,
    });
    expect(sent.map((entry) => entry.message.to)).toEqual(["u1@acme.test"]);
  });

  it("defaults to the subject's readers when the server has hooks but no audience", async () => {
    const reader = "00000000-0000-4000-8000-00000000000a";
    const outsider = "00000000-0000-4000-8000-00000000000b";
    const { transport: mail, sent } = recordingTransport();

    const { transport, calls } = fakeTransport({
      claim_notification_deliveries: claimOnce([
        delivery("d1", reader),
        delivery("d2", outsider),
      ]),
      subject_types: () => ["task"],
      can_subject_for: (args) => args["member"] === reader,
    });

    const notifications = createNotifications({
      transport,
      types,
      render: (item) => ({ title: item.summary ?? "" }),
      email: { transport: mail, from: "hi@acme.test" },
      server: {
        authorization: defineAuthorizationHooks({
          apiVersion: 1,
          name: "test",
        }),
      },
    });

    expect(await notifications.deliver()).toEqual({
      sent: 1,
      skipped: 1,
      failed: 0,
    });
    expect(sent.map((entry) => entry.message.to)).toEqual([
      `${reader}@acme.test`,
    ]);
    expect(calls).toContainEqual({
      fn: "can_subject_for",
      args: {
        member: outsider,
        subject_type: "task",
        subject_id: "42",
        action: "read",
      },
    });
  });

  it("sends to no one when audience throws, and retries the deliveries", async () => {
    const { transport: mail, sent } = recordingTransport();

    const { transport, completions } = fakeTransport({
      claim_notification_deliveries: claimOnce([
        delivery("d1", "u1"),
        delivery("d2", "u2"),
      ]),
    });

    const notifications = createNotifications({
      transport,
      types,
      render: (item) => ({ title: item.summary ?? "" }),
      email: { transport: mail, from: "hi@acme.test" },
      audience: () => {
        throw new Error("policy store down");
      },
    });

    expect(await notifications.deliver()).toEqual({
      sent: 0,
      skipped: 0,
      failed: 2,
    });
    expect(sent).toEqual([]);
    expect(completions()).toEqual([
      {
        delivery: "d1",
        status: "pending",
        error: "audience check failed: policy store down",
        max_attempts: 5,
      },
      {
        delivery: "d2",
        status: "pending",
        error: "audience check failed: policy store down",
        max_attempts: 5,
      },
    ]);
  });

  it("delivers to no one when audience returns something that is not a list", async () => {
    const { transport: mail, sent } = recordingTransport();

    const { transport } = fakeTransport({
      claim_notification_deliveries: claimOnce([delivery("d1", "u1")]),
    });

    const notifications = createNotifications({
      transport,
      types,
      render: (item) => ({ title: item.summary ?? "" }),
      email: { transport: mail, from: "hi@acme.test" },
      // @ts-expect-error -- a broken policy
      audience: () => "everyone",
    });

    expect((await notifications.deliver()).failed).toBe(1);
    expect(sent).toEqual([]);
  });

  it("refuses an email option next to a channel named email", () => {
    const { transport: mail } = recordingTransport();
    expect(() =>
      createNotifications({
        transport: fakeTransport().transport,
        types,
        email: { transport: mail, from: "hi@acme.test" },
        channels: [{ apiVersion: 1, name: "email", send: vi.fn() }],
      }),
    ).toThrow(/remove the channel named "email"/);
  });
});

describe("createNotifications delivery tracking", () => {
  it("stores the composed template key and puts the subject on delivered and failed", async () => {
    const { transport: mail } = recordingTransport();

    const { transport, completions } = fakeTransport({
      claim_notification_deliveries: claimOnce([
        delivery("d1", "u1"),
        delivery("d2", "u2", {
          notification: notification({
            id: "r2",
            event_id: "e2",
            subject_type: null,
            subject_id: null,
          }),
        }),
      ]),
    });

    const events = new EventHub();
    const seen: [string, unknown][] = [];
    events.on("block", (event) => seen.push([event.type, event.data]));

    const notifications = createNotifications({
      transport,
      types,
      events,
      email: {
        transport: {
          ...mail,
          send: (message, options) => {
            if (options.idempotencyKey === "d2") {
              throw new Error("smtp down");
            }

            return mail.send(message, options);
          },
        },
        from: "hi@acme.test",
        compose: () => ({ subject: "Assigned", templateKey: "assigned-v2" }),
      },
    });

    expect(await notifications.deliver()).toEqual({
      sent: 1,
      skipped: 0,
      failed: 1,
    });
    expect(completions()[0]).toEqual({
      delivery: "d1",
      status: "sent",
      provider: "fake",
      provider_message_id: "m-d1",
      template_key: "assigned-v2",
    });
    expect(seen).toEqual([
      [
        "notification.delivered",
        {
          notificationId: "e1",
          organizationId: "organization_1",
          type: "task.assigned",
          channel: "email",
          deliveryId: "d1",
          subjectType: "task",
          subjectId: "42",
        },
      ],
      [
        "notification.failed",
        expect.objectContaining({
          notificationId: "e2",
          deliveryId: "d2",
          subjectType: "notification",
          subjectId: "e2",
          error: "smtp down",
        }),
      ],
    ]);
  });

  it("records a provider event and emits it with the subject once", async () => {
    const answer = (recorded: boolean) => ({
      delivery_id: "d1",
      notification_id: "e1",
      tenant: "organization_1",
      type: "task.assigned",
      channel: "email",
      user_id: "u1",
      subject_type: "task",
      subject_id: "42",
      kind: "opened",
      provider_status: "clicked",
      recorded,
    });

    let first = true;

    const { transport, calls } = fakeTransport({
      record_delivery_event: () => {
        const recorded = first;
        first = false;

        return answer(recorded);
      },
    });

    const events = new EventHub();
    const seen: [string, unknown][] = [];
    events.on("block", (event) => seen.push([event.type, event.data]));
    const notifications = createNotifications({ transport, types, events });

    const input = {
      provider: "resend",
      providerMessageId: "re_1",
      kind: "opened",
      providerEventId: "msg_1",
      occurredAt: Temporal.Instant.from("2026-01-01T00:00:00Z"),
    } as const;

    expect(await notifications.recordDeliveryEvent(input).orThrow()).toEqual({
      deliveryId: "d1",
      notificationId: "e1",
      tenant: "organization_1",
      type: "task.assigned",
      channel: "email",
      userId: "u1",
      subject: { type: "task", id: "42" },
      kind: "opened",
      providerStatus: "clicked",
      recorded: true,
    });
    expect(
      (await notifications.recordDeliveryEvent(input).orThrow())?.recorded,
    ).toBe(false);
    expect(calls[0]).toEqual({
      fn: "record_delivery_event",
      args: {
        provider: "resend",
        provider_message_id: "re_1",
        kind: "opened",
        provider_event_id: "msg_1",
        occurred_at: "2026-01-01T00:00:00Z",
        detail: {},
        suppress: null,
      },
    });
    expect(seen).toEqual([
      [
        "notification.opened",
        {
          notificationId: "e1",
          organizationId: "organization_1",
          type: "task.assigned",
          channel: "email",
          deliveryId: "d1",
          provider: "resend",
          providerEventId: "msg_1",
          subjectType: "task",
          subjectId: "42",
        },
      ],
    ]);
  });

  it("returns null for an unknown message and lists a record's deliveries", async () => {
    const { transport, calls } = fakeTransport({
      list_subject_deliveries: () => [
        {
          id: "d1",
          notification_id: "e1",
          type: "task.assigned",
          channel: "email",
          user_id: "u1",
          status: "sent",
          provider: "resend",
          provider_message_id: "re_1",
          provider_status: "opened",
          provider_status_at: "2026-01-01T00:01:00Z",
          template_key: "assigned-v2",
          error: null,
          attempts: 1,
          created_at: "2026-01-01T00:00:00Z",
          delivered_at: "2026-01-01T00:00:01Z",
          events: [
            {
              kind: "delivered",
              occurred_at: "2026-01-01T00:00:30Z",
              detail: {},
            },
            { kind: "unknown", occurred_at: null, detail: null },
          ],
        },
        { id: "d2", notification_id: "e1", status: "weird" },
        "not a row",
      ],
    });

    const notifications = createNotifications({ transport, types });
    expect(
      await notifications
        .recordDeliveryEvent({
          provider: "resend",
          providerMessageId: "re_x",
          kind: "delivered",
        })
        .orThrow(),
    ).toBeNull();

    const [first, second, ...rest] = await notifications
      .subjectDeliveries({
        subject: { type: "task", id: "42" },
        tenant: "organization_1",
        limit: 5,
      })
      .orThrow();

    expect(rest).toEqual([]);
    expect(first).toMatchObject({
      id: "d1",
      status: "sent",
      providerStatus: "opened",
      templateKey: "assigned-v2",
      attempts: 1,
      events: [{ kind: "delivered", detail: {} }],
    });
    expect(first?.providerStatusAt?.toString()).toBe("2026-01-01T00:01:00Z");
    expect(second).toMatchObject({
      id: "d2",
      status: "pending",
      providerStatus: null,
      attempts: null,
      events: [],
    });
    expect(calls.at(-1)).toEqual({
      fn: "list_subject_deliveries",
      args: {
        subject_type: "task",
        subject_id: "42",
        tenant: "organization_1",
        max_items: 5,
      },
    });
  });
});

describe("createNotifications suppressions", () => {
  it("suppresses, lifts and lists through the module functions", async () => {
    const { transport, calls } = fakeTransport({
      suppress_notification_address: () => true,
      unsuppress_notification_address: () => false,
      list_notification_suppressions: () => [
        {
          channel: "email",
          address: "u1@acme.test",
          user_id: "u1",
          reason: "complaint",
          provider: "resend",
          created_at: "2026-01-01T00:00:00Z",
        },
        { channel: "email", address: "x@acme.test", reason: "unknown" },
        "not a row",
      ],
    });

    const notifications = createNotifications({ transport, types });
    expect(
      await notifications
        .suppress({ address: "U1@acme.test", reason: "bounce" })
        .orThrow(),
    ).toBe(true);
    expect(await notifications.unsuppress("u1@acme.test").orThrow()).toBe(
      false,
    );

    const [only, ...rest] = await notifications
      .suppressions({ limit: 10 })
      .orThrow();

    expect(rest).toEqual([]);
    expect(only).toMatchObject({
      channel: "email",
      address: "u1@acme.test",
      userId: "u1",
      reason: "complaint",
      provider: "resend",
    });
    expect(only?.createdAt?.toString()).toBe("2026-01-01T00:00:00Z");
    expect(calls.map((call) => [call.fn, call.args])).toEqual([
      [
        "suppress_notification_address",
        {
          address: "U1@acme.test",
          reason: "bounce",
          channel: "email",
          provider: null,
          provider_event_id: null,
          detail: {},
        },
      ],
      [
        "unsuppress_notification_address",
        { address: "u1@acme.test", channel: "email" },
      ],
      ["list_notification_suppressions", { max_items: 10 }],
    ]);
  });

  it("returns the database error of a refused suppression", async () => {
    const transport: BlockTransport = {
      async call() {
        throw new DbException(dbError("forbidden", "service only"));
      },
    };

    const result = await createNotifications({ transport, types }).suppress({
      address: "a@b.test",
      reason: "manual",
    });

    expect(result.ok).toBe(false);
    expect(result.error?.kind).toBe("forbidden");
  });
});

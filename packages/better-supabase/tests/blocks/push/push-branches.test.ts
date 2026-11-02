import { afterEach, describe, expect, it, vi } from "vitest";

import type { NotificationMessage } from "../../../src/blocks/notifications/channel.ts";
import type {
  BlockTransport,
  ExpoPush,
  ExpoPushMessage,
  PushDevices,
} from "../../../src/blocks/push/index.ts";

import {
  createPush,
  expoPush,
  expoPushChannel,
  registerDevice,
} from "../../../src/blocks/push/index.ts";

function transport(
  answer: (fn: string, args: Record<string, unknown>) => unknown,
) {
  const call = vi.fn(
    async (_schema: string, fn: string, args: Record<string, unknown>) =>
      answer(fn, args),
  );

  const value: BlockTransport = { call };

  return { call, transport: value };
}

function jsonResponse(
  body: unknown,
  init: ResponseInit = {},
): Promise<Response> {
  return Promise.resolve(Response.json(body, init));
}

const sleeps: number[] = [];

const sleep = async (milliseconds: number): Promise<void> => {
  sleeps.push(milliseconds);
};

afterEach(() => {
  sleeps.length = 0;
  vi.unstubAllGlobals();
  vi.useRealTimers();
});

describe("createPush branches", () => {
  it("reads counts that come back as text or null", async () => {
    const { transport: t } = transport((fn) =>
      fn === "prune_push_tokens" ? "3" : null,
    );

    const devices = createPush({ transport: t });

    expect(await devices.prune(["a"]).orThrow()).toBe(3);
    expect(
      await devices.recordTickets({ deliveryId: "d", tickets: [] }).orThrow(),
    ).toBe(0);
  });

  it("records tickets with ids and errors and defaults missing ones to null", async () => {
    const { call, transport: t } = transport(() => 2);
    const devices = createPush({ transport: t });

    await devices
      .recordTickets({
        deliveryId: "d1",
        tickets: [
          { token: "a", id: "r1" },
          { token: "b", error: "Boom" },
        ],
      })
      .orThrow();

    expect(call).toHaveBeenLastCalledWith(
      "better_supabase",
      "record_push_tickets",
      {
        delivery: "d1",
        tickets: [
          { token: "a", id: "r1", error: null },
          { token: "b", id: null, error: "Boom" },
        ],
      },
    );
  });

  it("checks receipts with the default sender, limit and age, and ignores malformed completions", async () => {
    const completions: unknown[] = [
      { events: "nope" },
      { events: [{ nothing: true }, "text"] },
      {},
    ];

    const { call, transport: t } = transport((fn) => {
      if (fn === "unchecked_push_tickets") {
        return [];
      }

      return completions.shift();
    });

    const devices = createPush({
      transport: t,
      logger: {
        error: () => undefined,
        warn: () => undefined,
        info: () => undefined,
        debug: () => undefined,
      },
    });

    const withReceipt: ExpoPush = {
      send: vi.fn(),
      checkReceipts: async () => ({
        delivered: 1,
        failed: [],
        pruned: 0,
        receipts: [{ id: "r1", token: "a", status: "ok" as const }],
      }),
    };

    for (let round = 0; round < 3; round += 1) {
      await devices.checkReceipts({ push: withReceipt }).orThrow();
    }

    const result = await devices
      .checkReceipts({
        limit: 5,
        olderThan: Temporal.Duration.from({ minutes: 2 }),
      })
      .orThrow();

    expect(result).toEqual({
      delivered: 0,
      failed: [],
      pruned: 0,
      receipts: [],
    });
    expect(call).toHaveBeenCalledWith(
      "better_supabase",
      "unchecked_push_tickets",
      { max_items: 5, older_than: "PT2M" },
    );

    await devices.checkReceipts().orThrow();
    expect(call).toHaveBeenLastCalledWith(
      "better_supabase",
      "unchecked_push_tickets",
      { max_items: 1000, older_than: "PT15M" },
    );
  });

  it("completes receipts with a missing error and message as null and skips unrecorded events", async () => {
    const { call, transport: t } = transport((fn) => {
      if (fn === "unchecked_push_tickets") {
        return [{ id: "r1", token: "a" }];
      }

      return { events: "none" };
    });

    const devices = createPush({ transport: t });

    const push: ExpoPush = {
      send: vi.fn(),
      checkReceipts: vi.fn(async () => ({
        delivered: 1,
        failed: [],
        pruned: 0,
        receipts: [
          { id: "r1", token: "a", status: "ok" as const },
          {
            id: "r2",
            token: "b",
            status: "error" as const,
            error: "MessageTooBig",
            message: "big",
          },
        ],
      })),
    };

    await devices.checkReceipts({ push }).orThrow();

    expect(call).toHaveBeenLastCalledWith(
      "better_supabase",
      "complete_push_receipts",
      {
        receipts: [
          { id: "r1", status: "ok", error: null, message: null },
          { id: "r2", status: "error", error: "MessageTooBig", message: "big" },
        ],
      },
    );
  });
});

describe("registerDevice without names", () => {
  it("leaves out the device name and app version", async () => {
    const register = vi.fn(() => ({ orThrow: async () => "d1" }));
    // SAFETY: the test calls register only.
    const devices = { register } as unknown as PushDevices;

    await registerDevice({
      notifications: {
        getPermissionsAsync: async () => ({ status: "granted" }),
        requestPermissionsAsync: async () => ({ status: "granted" }),
        getExpoPushTokenAsync: async () => ({ data: "tok" }),
      },
      devices,
      platform: "ios",
    }).orThrow();

    expect(register).toHaveBeenCalledWith({
      token: "tok",
      platform: "ios",
      provider: "expo",
    });
  });
});

describe("expoPush branches", () => {
  it("sends the access token, uses global fetch and reads an empty body as no data", async () => {
    const seen: Headers[] = [];

    vi.stubGlobal(
      "fetch",
      vi.fn(async (_url: unknown, init?: RequestInit) => {
        seen.push(new Headers(init?.headers));

        return new Response("", { status: 200 });
      }),
    );

    const push = expoPush({ accessToken: "secret", sleep });
    const tickets = await push.send(["a"], { title: "t" });

    expect(seen[0]?.get("authorization")).toBe("Bearer secret");
    expect(tickets).toEqual([{ token: "a", error: "Unknown" }]);
  });

  it("waits for a Retry-After date, and falls back to backoff for junk or past values", async () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date("2026-10-31T12:00:00Z"));

    const retryAfters = [
      "Sat, 31 Oct 2026 12:00:07 GMT",
      "not a date",
      "-5",
      "100",
    ];

    const fetch = vi.fn(async () => {
      const header = retryAfters.shift();

      return header === undefined
        ? Response.json({ data: [{ status: "ok", id: "r" }] })
        : new Response("slow", {
            status: 503,
            headers: { "retry-after": header },
          });
    });

    const push = expoPush({ fetch, sleep, maxRetries: 5 });
    const tickets = await push.send(["a"], { title: "t" });

    expect(tickets).toEqual([{ token: "a", id: "r" }]);
    expect(sleeps).toEqual([7000, 2000, 4000, 30_000]);
  });

  it("reports a non-Error failure and a long message in a request-failed ticket", async () => {
    const fetch = vi.fn(() => Promise.reject<Response>("plain failure"));

    const push = expoPush({ fetch, sleep, maxRetries: 0 });

    expect(await push.send(["a", "b"], { title: "t" })).toEqual([
      { token: "a", error: "RequestFailed", message: "plain failure" },
      { token: "b", error: "RequestFailed", message: "plain failure" },
    ]);
  });

  it("maps entries that are missing, unsuccessful or carry details", async () => {
    const fetch = vi.fn(async () =>
      Response.json({
        data: [
          { status: "ok" },
          {
            status: "error",
            message: "bad",
            details: { error: "MessageTooBig" },
          },
          { status: "error", details: { error: 5 } },
        ],
      }),
    );

    const push = expoPush({ fetch, sleep });

    expect(await push.send(["a", "b", "c", "d"], { title: "t" })).toEqual([
      { token: "a", error: "Unknown" },
      { token: "b", error: "MessageTooBig", message: "bad" },
      { token: "c", error: "Unknown" },
      { token: "d", error: "Unknown" },
    ]);
  });

  it("treats a non-array response as no tickets", async () => {
    const fetch = vi.fn(() => jsonResponse({ data: { oops: true } }));
    const push = expoPush({ fetch, sleep });

    expect(await push.send(["a"], { title: "t" })).toEqual([
      { token: "a", error: "Unknown" },
    ]);
  });

  it("reuses stored tickets, skips a fully sent chunk and prunes only fresh unregistered tokens", async () => {
    const fetch = vi.fn(() => jsonResponse({ data: [] }));
    const prune = vi.fn(() => ({ orThrow: async () => 1 }));
    // SAFETY: the test calls prune only.
    const devices = { prune } as unknown as PushDevices;
    const push = expoPush({ fetch, sleep, devices });

    const tickets = await push.send(
      ["a", "b"],
      { title: "t" },
      {
        sent: [
          { token: "a", id: "r1" },
          { token: "b", error: "DeviceNotRegistered" },
          { token: "z", error: "MessageTooBig" },
        ],
      },
    );

    expect(tickets).toEqual([
      { token: "a", id: "r1" },
      { token: "b", error: "DeviceNotRegistered" },
    ]);
    expect(fetch).not.toHaveBeenCalled();
    expect(prune).not.toHaveBeenCalled();
  });

  it("checks receipts: skips tickets without id, missing receipts and keeps error messages", async () => {
    const fetch = vi.fn(() =>
      jsonResponse({
        data: {
          r1: { status: "ok" },
          r2: {
            status: "error",
            message: "gone",
            details: { error: "DeviceNotRegistered" },
          },
          r3: { status: "error" },
        },
      }),
    );

    const push = expoPush({ fetch, sleep });

    const result = await push.checkReceipts([
      { token: "a", id: "r1" },
      { token: "b", id: "r2" },
      { token: "c", id: "r3" },
      { token: "d", id: "r4" },
      { token: "e" },
    ]);

    expect(result.delivered).toBe(1);
    expect(result.pruned).toBe(0);
    expect(result.receipts).toEqual([
      { id: "r1", token: "a", status: "ok" },
      {
        id: "r2",
        token: "b",
        status: "error",
        error: "DeviceNotRegistered",
        message: "gone",
      },
      { id: "r3", token: "c", status: "error", error: "Unknown" },
    ]);
    expect(result.failed).toEqual([
      { token: "b", id: "r2", error: "DeviceNotRegistered", message: "gone" },
      { token: "c", id: "r3", error: "Unknown" },
    ]);
  });
});

describe("expoPush default sleep", () => {
  it("waits on a timer between retries", async () => {
    vi.useFakeTimers();

    let calls = 0;

    const fetch = vi.fn(async () => {
      calls += 1;

      return calls === 1
        ? new Response("busy", { status: 429, headers: { "retry-after": "0" } })
        : Response.json({ data: [{ status: "ok", id: "r" }] });
    });

    const push = expoPush({ fetch, maxRetries: 1 });
    const pending = push.send(["a"], { title: "t" });

    await vi.runAllTimersAsync();
    expect(await pending).toEqual([{ token: "a", id: "r" }]);
    expect(calls).toBe(2);
  });
});

describe("expoPushChannel branches", () => {
  const message: NotificationMessage = {
    deliveryId: "dl1",
    channel: "push",
    attempts: 1,
    userId: "u1",
    locale: null,
    email: null,
    notification: {
      id: "n1",
      recipientId: "n1",
      eventId: "e1",
      type: "comment.created",
      data: {},
      tenant: null,
      actorId: null,
      subject: null,
      summary: null,
      actionPath: null,
      priority: null,
      createdAt: Temporal.Instant.from("2026-01-01T00:00:00Z"),
      readAt: null,
      resolvedAt: null,
      resolution: null,
      actions: [],
      fields: {},
    },
  };

  const devices = (): PushDevices => {
    const { transport: t } = transport((fn) =>
      fn === "push_tokens_for"
        ? [{ userId: "u1", token: "a", platform: "ios", provider: "expo" }]
        : fn === "push_tickets_for"
          ? []
          : 1,
    );

    return createPush({ transport: t });
  };

  it("falls back to the type for the title and leaves out empty body and action path", async () => {
    const send = vi.fn(
      async (tokens: readonly string[], _message: ExpoPushMessage) =>
        tokens.map((token) => ({ token, id: "r" })),
    );

    const channel = expoPushChannel({
      devices: devices(),
      push: { send, checkReceipts: vi.fn() },
      name: "mobile",
    });

    expect(channel.name).toBe("mobile");
    await channel.send(message);
    expect(send.mock.calls[0]?.[1]).toEqual({
      title: "comment.created",
      sound: "default",
      data: { notificationId: "n1", type: "comment.created" },
    });
  });

  it("uses the summary for the title and a custom message builder", async () => {
    const send = vi.fn(
      async (tokens: readonly string[], _message: ExpoPushMessage) =>
        tokens.map((token) => ({ token, id: "r" })),
    );

    const withSummary = expoPushChannel({
      devices: devices(),
      push: { send, checkReceipts: vi.fn() },
    });

    await withSummary.send({
      ...message,
      notification: { ...message.notification, summary: "Summary" },
    });
    expect(send.mock.calls[0]?.[1]).toMatchObject({ title: "Summary" });

    const custom = expoPushChannel({
      devices: devices(),
      push: { send, checkReceipts: vi.fn() },
      message: () => ({ title: "Custom" }),
    });

    await custom.send(message);
    expect(send.mock.calls[1]?.[1]).toEqual({ title: "Custom" });
  });

  it("throws a request failure with or without a message", async () => {
    const run = (failure: { message?: string }) =>
      expoPushChannel({
        devices: devices(),
        push: {
          send: async () => [
            { token: "a", error: "RequestFailed", ...failure },
          ],
          checkReceipts: vi.fn(),
        },
        storeTickets: false,
      }).send(message);

    await expect(run({ message: "timeout" })).rejects.toThrow(
      "Expo push request failed: timeout",
    );
    await expect(run({})).rejects.toThrow(
      "Expo push request failed: RequestFailed",
    );
  });

  it("throws a rejection with its error and message, or Unknown, and skips unregistered devices", async () => {
    const run = (ticket: { error?: string; message?: string }) =>
      expoPushChannel({
        devices: devices(),
        push: {
          send: async () => [{ token: "a", ...ticket }],
          checkReceipts: vi.fn(),
        },
        storeTickets: false,
      }).send(message);

    await expect(
      run({ error: "MessageTooBig", message: "big" }),
    ).rejects.toThrow("Expo rejected the push: MessageTooBig (big)");
    await expect(run({ error: "MessageTooBig" })).rejects.toThrow(
      "Expo rejected the push: MessageTooBig",
    );
    await expect(run({})).rejects.toThrow("Expo rejected the push: Unknown");
    expect(await run({ error: "DeviceNotRegistered" })).toEqual({
      status: "skipped",
      provider: "expo",
    });
  });
});

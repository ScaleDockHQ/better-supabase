import * as v from "valibot";
import { describe, expect, expectTypeOf, it, vi } from "vitest";

import type { NotificationMessage } from "../../../src/blocks/notifications/channel.ts";
import type {
  BlockTransport,
  PushDevices,
} from "../../../src/blocks/push/index.ts";

import {
  createPush,
  expoPush,
  expoPushChannel,
  registerDevice,
  unregisterOnSignOut,
} from "../../../src/blocks/push/index.ts";
import { ok } from "../../../src/core/result.ts";

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

function expoFetch(
  answer: (path: string, body: unknown) => unknown,
  status: number | (() => number) = 200,
  headers: Record<string, string> = {},
) {
  const calls: { path: string; body: unknown; headers: Headers }[] = [];

  const fetch = vi.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
    const path = String(input).split("/").at(-1) ?? "";
    const body: unknown = JSON.parse(String(init?.body));
    calls.push({ path, body, headers: new Headers(init?.headers) });

    return Response.json(
      { data: answer(path, body) },
      { status: typeof status === "number" ? status : status(), headers },
    );
  });

  return { calls, fetch };
}

const noSleep = vi.fn(async (_milliseconds: number) => undefined);

describe("createPush", () => {
  it("maps calls to the module functions", async () => {
    const { call, transport: t } = transport((fn) => {
      if (fn === "register_push_device") {
        return "d1";
      }

      if (fn === "unregister_push_device") {
        return true;
      }

      if (fn === "prune_push_tokens") {
        return 2;
      }

      return [
        { userId: "u1", token: "a", platform: "ios", provider: "expo" },
        { userId: "u1", token: "b", platform: "tv", provider: "expo" },
      ];
    });

    const devices = createPush({ transport: t, schema: "app" });
    expect(
      await devices.register({ token: "a", platform: "ios" }).orThrow(),
    ).toBe("d1");
    expect(call).toHaveBeenLastCalledWith("app", "register_push_device", {
      token: "a",
      platform: "ios",
      provider: "expo",
      device_name: undefined,
      app_version: undefined,
    });
    expect(await devices.unregister("a").orThrow()).toBe(true);
    expect(await devices.tokensFor(["u1"]).orThrow()).toEqual([
      {
        userId: "u1",
        token: "a",
        platform: "ios",
        provider: "expo",
        fields: {},
      },
    ]);
    expect(call).toHaveBeenLastCalledWith("app", "push_tokens_for", {
      users: ["u1"],
    });
    expect(await devices.prune(["a", "b"]).orThrow()).toBe(2);
  });

  it("stores tickets and reads them back", async () => {
    const { call, transport: t } = transport((fn) =>
      fn === "record_push_tickets"
        ? 2
        : [
            { token: "a", id: "r1", error: null },
            { token: "b", id: null, error: "MessageTooBig" },
          ],
    );

    const devices = createPush({ transport: t });
    expect(
      await devices
        .recordTickets("dl1", [
          { token: "a", id: "r1" },
          { token: "b", error: "MessageTooBig", message: "too big" },
        ])
        .orThrow(),
    ).toBe(2);
    expect(call).toHaveBeenLastCalledWith(
      "better_supabase",
      "record_push_tickets",
      {
        delivery: "dl1",
        tickets: [
          { token: "a", id: "r1", error: null },
          { token: "b", id: null, error: "MessageTooBig" },
        ],
      },
    );
    expect(await devices.ticketsFor("dl1").orThrow()).toEqual([
      { token: "a", id: "r1" },
      { token: "b", error: "MessageTooBig" },
    ]);
  });

  it("checks receipts of unchecked tickets and completes them", async () => {
    const { call, transport: t } = transport((fn) =>
      fn === "unchecked_push_tickets"
        ? [{ id: "r1", token: "a", deliveryId: "dl1" }]
        : 1,
    );

    const checkReceipts = vi.fn(async () => ({
      delivered: 0,
      failed: [{ token: "a", id: "r1", error: "DeviceNotRegistered" }],
      pruned: 1,
      receipts: [
        {
          id: "r1",
          token: "a",
          status: "error" as const,
          error: "DeviceNotRegistered",
        },
      ],
    }));

    const devices = createPush({ transport: t });

    const result = await devices
      .checkReceipts({
        push: { send: vi.fn(), checkReceipts },
        limit: 50,
        olderThan: Temporal.Duration.from({ minutes: 30 }),
      })
      .orThrow();

    expect(result.pruned).toBe(1);
    expect(call.mock.calls[0]?.slice(1)).toEqual([
      "unchecked_push_tickets",
      { max_items: 50, older_than: "PT30M" },
    ]);
    expect(checkReceipts).toHaveBeenCalledWith([{ id: "r1", token: "a" }]);
    expect(call).toHaveBeenLastCalledWith(
      "better_supabase",
      "complete_push_receipts",
      {
        receipts: [
          {
            id: "r1",
            status: "error",
            error: "DeviceNotRegistered",
            message: null,
          },
        ],
      },
    );
  });

  it("skips completing when Expo has no receipts ready", async () => {
    const { call, transport: t } = transport(() => []);

    const devices = createPush({ transport: t });

    const checkReceipts = vi.fn(async () => ({
      delivered: 0,
      failed: [],
      pruned: 0,
      receipts: [],
    }));

    await devices
      .checkReceipts({ push: { send: vi.fn(), checkReceipts } })
      .orThrow();
    expect(call).toHaveBeenCalledOnce();
    expect(call.mock.calls[0]?.[2]).toEqual({
      max_items: 1000,
      older_than: "PT15M",
    });
  });
});

describe("push fields", () => {
  const schema = v.object({ channel: v.picklist(["stable", "beta"]) });

  it("validates fields before registering and parses them on reads", async () => {
    const { call, transport: t } = transport((fn) =>
      fn === "register_push_device"
        ? "d1"
        : [
            {
              userId: "u1",
              token: "a",
              platform: "ios",
              provider: "expo",
              fields: { channel: "beta" },
            },
          ],
    );

    const devices = createPush({ transport: t, fields: schema });

    const bad = await devices.register({
      token: "a",
      platform: "ios",
      // @ts-expect-error not one of the channels
      fields: { channel: "nightly" },
    });

    expect(bad).toMatchObject({ ok: false, error: { kind: "validation" } });
    expect(call).not.toHaveBeenCalled();
    await devices
      .register({ token: "a", platform: "ios", fields: { channel: "beta" } })
      .orThrow();
    expect(call.mock.calls[0]?.[2]).toMatchObject({
      fields: { channel: "beta" },
    });
    const [target] = await devices.tokensFor(["u1"]).orThrow();
    expectTypeOf(target?.fields.channel).toEqualTypeOf<
      "stable" | "beta" | undefined
    >();
    expect(target?.fields).toEqual({ channel: "beta" });
  });

  it("rejects a read whose fields fail the schema", async () => {
    const { transport: t } = transport(() => [
      {
        userId: "u1",
        token: "a",
        platform: "ios",
        provider: "expo",
        fields: { channel: 3 },
      },
    ]);

    const devices = createPush({ transport: t, fields: schema });
    expect(await devices.tokensFor(["u1"])).toMatchObject({
      ok: false,
      error: { kind: "validation" },
    });
  });
});

describe("registerDevice", () => {
  const devices = (): PushDevices & { register: ReturnType<typeof vi.fn> } => {
    const register = vi.fn(() => ({ orThrow: async () => "d1" }));

    // SAFETY: the tests call register only.
    return { register } as never;
  };

  it("asks for permission, then registers the Expo token", async () => {
    const d = devices();

    const notifications = {
      getPermissionsAsync: vi.fn(async () => ({ status: "undetermined" })),
      requestPermissionsAsync: vi.fn(async () => ({ status: "granted" })),
      getExpoPushTokenAsync: vi.fn(async () => ({
        data: "ExponentPushToken[x]",
      })),
    };

    expect(
      await registerDevice({
        notifications,
        devices: d,
        platform: "android",
        projectId: "p1",
        deviceName: "Pixel",
        appVersion: "1.2.0",
      }).orThrow(),
    ).toEqual({ deviceId: "d1", token: "ExponentPushToken[x]" });
    expect(notifications.getExpoPushTokenAsync).toHaveBeenCalledWith({
      projectId: "p1",
    });
    expect(d.register).toHaveBeenCalledWith({
      token: "ExponentPushToken[x]",
      platform: "android",
      provider: "expo",
      deviceName: "Pixel",
      appVersion: "1.2.0",
    });
  });

  it("resolves null when denied, without asking when request is false, or off a phone", async () => {
    const d = devices();

    const notifications = {
      getPermissionsAsync: vi.fn(async () => ({ status: "denied" })),
      requestPermissionsAsync: vi.fn(async () => ({ status: "denied" })),
      getExpoPushTokenAsync: vi.fn(async () => ({ data: "t" })),
    };

    expect(
      await registerDevice({
        notifications,
        devices: d,
        platform: "ios",
      }).orThrow(),
    ).toBeNull();
    expect(
      await registerDevice({
        notifications,
        devices: d,
        platform: "ios",
        request: false,
      }).orThrow(),
    ).toBeNull();
    expect(notifications.requestPermissionsAsync).toHaveBeenCalledOnce();
    expect(
      await registerDevice({
        notifications,
        devices: d,
        platform: "macos",
      }).orThrow(),
    ).toBeNull();
    expect(d.register).not.toHaveBeenCalled();
  });

  it("returns a DbError when the token can't be read", async () => {
    const result = await registerDevice({
      notifications: {
        getPermissionsAsync: async () => ({ status: "granted" }),
        requestPermissionsAsync: async () => ({ status: "granted" }),
        getExpoPushTokenAsync: async () => {
          throw new Error("no projectId");
        },
      },
      devices: devices(),
      platform: "ios",
    });

    expect(result.ok ? undefined : result.error.message).toBe("no projectId");
  });
});

describe("unregisterOnSignOut", () => {
  it("unregisters the token before signing out", async () => {
    const order: string[] = [];

    const unregister = vi.fn(() => {
      order.push("unregister");

      return Promise.resolve(ok(true));
    });

    // SAFETY: the test calls unregister only.
    const devices = { unregister } as never as PushDevices;

    const signOut = unregisterOnSignOut({
      signOut: async () => {
        order.push("signOut");

        return { error: null };
      },
      devices,
      token: () => "t1",
    });

    expect(await signOut()).toEqual({ error: null });
    expect(order).toEqual(["unregister", "signOut"]);
    await unregisterOnSignOut({
      signOut: async () => undefined,
      devices,
      token: () => null,
    })();
    expect(unregister).toHaveBeenCalledOnce();
  });
});

describe("expoPush", () => {
  it("sends in chunks of 100 and prunes unregistered tokens from tickets", async () => {
    const pruned: string[][] = [];

    const devices = createPush({
      transport: transport((fn, args) => {
        if (fn === "prune_push_tokens") {
          pruned.push([...(args["tokens"] as string[])]);

          return 1;
        }

        return null;
      }).transport,
    });

    const { calls, fetch } = expoFetch((_path, body) =>
      (body as { to: string }[]).map((message) =>
        message.to === "gone"
          ? {
              status: "error",
              message: "not registered",
              details: { error: "DeviceNotRegistered" },
            }
          : { status: "ok", id: `r-${message.to}` },
      ),
    );

    const push = expoPush({ accessToken: "secret", devices, fetch });
    const tokens = [...Array.from({ length: 100 }, (_, i) => `t${i}`), "gone"];
    const tickets = await push.send(tokens, { title: "Hi" });
    expect(calls.map((call) => call.path)).toEqual(["send", "send"]);
    expect(calls[0]?.headers.get("authorization")).toBe("Bearer secret");
    expect((calls[1]?.body as unknown[] | undefined)?.[0]).toEqual({
      title: "Hi",
      to: "gone",
    });
    expect(tickets).toHaveLength(101);
    expect(tickets[0]).toEqual({ token: "t0", id: "r-t0" });
    expect(tickets[100]).toEqual({
      token: "gone",
      error: "DeviceNotRegistered",
      message: "not registered",
    });
    expect(pruned).toEqual([["gone"]]);
  });

  it("reads receipts and prunes devices Expo no longer reaches", async () => {
    const prune = vi.fn(() => ({ orThrow: async () => 1 }));
    // SAFETY: the sender calls prune only.
    const devices = { prune } as never as PushDevices;

    const { calls, fetch } = expoFetch(() => ({
      r1: { status: "ok" },
      r2: { status: "error", details: { error: "DeviceNotRegistered" } },
      r3: {
        status: "error",
        message: "too big",
        details: { error: "MessageTooBig" },
      },
    }));

    const result = await expoPush({ devices, fetch }).checkReceipts([
      { token: "a", id: "r1" },
      { token: "b", id: "r2" },
      { token: "c", id: "r3" },
      { token: "d", id: "r4" },
      { token: "e", error: "InvalidCredentials" },
    ]);

    expect(calls[0]).toMatchObject({
      path: "getReceipts",
      body: { ids: ["r1", "r2", "r3", "r4"] },
    });
    expect(result).toEqual({
      delivered: 1,
      failed: [
        { token: "b", id: "r2", error: "DeviceNotRegistered" },
        { token: "c", id: "r3", error: "MessageTooBig", message: "too big" },
      ],
      pruned: 1,
      receipts: [
        { id: "r1", token: "a", status: "ok" },
        { id: "r2", token: "b", status: "error", error: "DeviceNotRegistered" },
        {
          id: "r3",
          token: "c",
          status: "error",
          error: "MessageTooBig",
          message: "too big",
        },
      ],
    });
    expect(prune).toHaveBeenCalledWith(["b"]);
  });

  it("turns a chunk that keeps failing into RequestFailed tickets", async () => {
    const { calls, fetch } = expoFetch(() => null, 500);

    const tickets = await expoPush({ fetch, sleep: noSleep }).send(["a"], {});

    expect(calls).toHaveLength(4);
    expect(tickets).toEqual([
      {
        token: "a",
        error: "RequestFailed",
        message: expect.stringContaining("Expo Push API send answered 500"),
      },
    ]);
    expect(noSleep.mock.calls.map(([ms]) => ms)).toEqual([1000, 2000, 4000]);
  });

  it("does not retry a 4xx and throws when receipts can't be read", async () => {
    const { calls, fetch } = expoFetch(() => null, 400);

    expect(
      (await expoPush({ fetch, sleep: noSleep }).send(["a"], {}))[0]?.error,
    ).toBe("RequestFailed");
    expect(calls).toHaveLength(1);
    await expect(
      expoPush({ fetch, sleep: noSleep }).checkReceipts([
        { token: "a", id: "r1" },
      ]),
    ).rejects.toThrow("Expo Push API getReceipts answered 400");
  });

  it("honours Retry-After on a 429, then succeeds", async () => {
    noSleep.mockClear();
    let attempt = 0;

    const { fetch } = expoFetch(
      () => [{ status: "ok", id: "r1" }],
      () => {
        attempt += 1;

        return attempt === 1 ? 429 : 200;
      },
      { "retry-after": "7" },
    );

    expect(await expoPush({ fetch, sleep: noSleep }).send(["a"], {})).toEqual([
      { token: "a", id: "r1" },
    ]);
    expect(noSleep).toHaveBeenCalledWith(7000);
  });

  it("retries a network error and keeps tickets of chunks already sent", async () => {
    let attempt = 0;

    const fetch = vi.fn(
      async (_input: RequestInfo | URL, init?: RequestInit) => {
        attempt += 1;

        if (attempt > 1) {
          throw new TypeError("network down");
        }

        const body = JSON.parse(String(init?.body)) as { to: string }[];

        return Response.json({
          data: body.map((m) => ({ status: "ok", id: `r-${m.to}` })),
        });
      },
    );

    const tokens = Array.from({ length: 101 }, (_, i) => `t${i}`);

    const tickets = await expoPush({
      fetch,
      sleep: noSleep,
      maxRetries: 1,
    }).send(tokens, {});

    expect(fetch).toHaveBeenCalledTimes(3);
    expect(tickets[0]).toEqual({ token: "t0", id: "r-t0" });
    expect(tickets[100]).toEqual({
      token: "t100",
      error: "RequestFailed",
      message: "network down",
    });
  });

  it("sends an idempotency key per chunk and skips tokens already sent", async () => {
    const { calls, fetch } = expoFetch((_path, body) =>
      (body as { to: string }[]).map((m) => ({
        status: "ok",
        id: `r-${m.to}`,
      })),
    );

    const tokens = Array.from({ length: 102 }, (_, i) => `t${i}`);

    const sent = Array.from({ length: 100 }, (_, i) => ({
      token: `t${i}`,
      id: `old-${i}`,
    }));

    const tickets = await expoPush({ fetch }).send(
      tokens,
      {},
      {
        idempotencyKey: "dl1",
        sent: [
          ...sent.slice(1),
          { token: "t0", error: "RequestFailed" },
          { token: "t101", error: "DeviceNotRegistered" },
        ],
      },
    );

    expect(calls).toHaveLength(2);
    expect(calls[0]?.headers.get("idempotency-key")).toBe("dl1:0");
    expect(calls[0]?.body).toEqual([{ to: "t0" }]);
    expect(calls[1]?.headers.get("idempotency-key")).toBe("dl1:1");
    expect(calls[1]?.body).toEqual([{ to: "t100" }]);
    expect(tickets).toHaveLength(102);
    expect(tickets[0]).toEqual({ token: "t0", id: "r-t0" });
    expect(tickets[1]).toEqual({ token: "t1", id: "old-1" });
    expect(tickets[101]).toEqual({
      token: "t101",
      error: "DeviceNotRegistered",
    });
  });
});

describe("expoPushChannel", () => {
  const message: NotificationMessage = {
    deliveryId: "dl1",
    channel: "push",
    attempts: 1,
    userId: "u1",
    locale: null,
    email: null,
    notification: {
      id: "n1",
      eventId: "e1",
      type: "comment.created",
      data: {},
      tenant: null,
      actorId: null,
      subject: null,
      summary: "New comment",
      actionPath: "/posts/1",
      priority: null,
      createdAt: Temporal.Instant.from("2026-01-01T00:00:00Z"),
      readAt: null,
      resolvedAt: null,
      resolution: null,
      actions: [],
      fields: {},
    },
    text: { title: "Ada commented", body: "Looks good" },
  };

  const recorded: unknown[] = [];

  const devicesWith = (
    tokens: readonly { token: string; provider: string }[],
    stored: readonly unknown[] = [],
  ) =>
    createPush({
      transport: transport((fn, args) => {
        if (fn === "push_tickets_for") {
          return stored;
        }

        if (fn === "record_push_tickets") {
          recorded.push(args);

          return 1;
        }

        return tokens.map((t) => ({ userId: "u1", platform: "ios", ...t }));
      }).transport,
    });

  it("pushes the rendered text to the user's Expo devices", async () => {
    const send = vi.fn(async (tokens: readonly string[]) =>
      tokens.map((token) => ({ token, id: `r-${token}` })),
    );

    const onTickets = vi.fn();

    const channel = expoPushChannel({
      devices: devicesWith([
        { token: "a", provider: "expo" },
        { token: "f", provider: "fcm" },
      ]),
      push: { send, checkReceipts: vi.fn() },
      onTickets,
    });

    expect(channel).toMatchObject({ apiVersion: 1, name: "push" });
    expect(await channel.send(message)).toEqual({
      provider: "expo",
      providerMessageId: "r-a",
    });
    expect(send).toHaveBeenCalledWith(
      ["a"],
      {
        title: "Ada commented",
        body: "Looks good",
        sound: "default",
        data: {
          notificationId: "n1",
          type: "comment.created",
          actionPath: "/posts/1",
        },
      },
      { idempotencyKey: "dl1", sent: [] },
    );
    expect(recorded.at(-1)).toEqual({
      delivery: "dl1",
      tickets: [{ token: "a", id: "r-a", error: null }],
    });
    expect(onTickets).toHaveBeenCalledWith(
      [{ token: "a", id: "r-a" }],
      message,
    );
  });

  it("skips users without devices and retries when Expo rejects every message", async () => {
    const push = {
      send: vi.fn(async (tokens: readonly string[]) =>
        tokens.map((token) => ({ token, error: "MessageRateExceeded" })),
      ),
      checkReceipts: vi.fn(),
    };

    expect(
      await expoPushChannel({ devices: devicesWith([]), push }).send(message),
    ).toEqual({ status: "skipped", provider: "expo" });
    await expect(
      expoPushChannel({
        devices: devicesWith([{ token: "a", provider: "expo" }]),
        push,
        name: "mobile",
      }).send(message),
    ).rejects.toThrow("MessageRateExceeded");
    push.send.mockResolvedValueOnce([
      { token: "a", error: "DeviceNotRegistered" },
    ]);
    expect(
      await expoPushChannel({
        devices: devicesWith([{ token: "a", provider: "expo" }]),
        push,
        message: () => ({ title: "custom" }),
      }).send(message),
    ).toEqual({ status: "skipped", provider: "expo" });
    expect(push.send).toHaveBeenLastCalledWith(
      ["a"],
      { title: "custom" },
      { idempotencyKey: "dl1", sent: [] },
    );
  });

  it("passes stored tickets on a retry and throws when a request failed", async () => {
    const send = vi.fn(async () => [
      { token: "a", id: "old" },
      { token: "b", error: "RequestFailed", message: "Expo answered 503" },
    ]);

    const channel = expoPushChannel({
      devices: devicesWith(
        [
          { token: "a", provider: "expo" },
          { token: "b", provider: "expo" },
        ],
        [{ token: "a", id: "old", error: null }],
      ),
      push: { send, checkReceipts: vi.fn() },
    });

    await expect(channel.send(message)).rejects.toThrow("Expo answered 503");
    expect(send).toHaveBeenCalledWith(["a", "b"], expect.anything(), {
      idempotencyKey: "dl1",
      sent: [{ token: "a", id: "old" }],
    });
    expect(recorded.at(-1)).toMatchObject({ delivery: "dl1" });
  });

  it("leaves tickets alone with storeTickets false", async () => {
    const { call, transport: t } = transport((fn) =>
      fn === "push_tokens_for"
        ? [{ userId: "u1", token: "a", platform: "ios", provider: "expo" }]
        : null,
    );

    const send = vi.fn(async () => [{ token: "a", id: "r1" }]);

    expect(
      await expoPushChannel({
        devices: createPush({ transport: t }),
        push: { send, checkReceipts: vi.fn() },
        storeTickets: false,
      }).send(message),
    ).toEqual({ provider: "expo", providerMessageId: "r1" });
    expect(call).toHaveBeenCalledOnce();
  });
});

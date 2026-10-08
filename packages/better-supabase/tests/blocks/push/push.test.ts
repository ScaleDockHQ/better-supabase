import { describe, expect, it, vi } from "vitest";

import type { NotificationMessage } from "../../../src/blocks/notifications/channel.ts";
import type {
  BlockTransport,
  PushDevices,
} from "../../../src/blocks/push/index.ts";

import {
  createPushDevices,
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
  status = 200,
) {
  const calls: { path: string; body: unknown; headers: Headers }[] = [];
  const fetch = vi.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
    const path = String(input).split("/").at(-1) ?? "";
    const body: unknown = JSON.parse(String(init?.body));
    calls.push({ path, body, headers: new Headers(init?.headers) });
    return new Response(JSON.stringify({ data: answer(path, body) }), {
      status,
    });
  });
  return { calls, fetch };
}

describe("createPushDevices", () => {
  it("maps calls to the module functions", async () => {
    const { call, transport: t } = transport((fn) => {
      if (fn === "register_push_device") return "d1";
      if (fn === "unregister_push_device") return true;
      if (fn === "prune_push_tokens") return 2;
      return [
        { userId: "u1", token: "a", platform: "ios", provider: "expo" },
        { userId: "u1", token: "b", platform: "tv", provider: "expo" },
      ];
    });
    const devices = createPushDevices({ transport: t, schema: "app" });
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
      { userId: "u1", token: "a", platform: "ios", provider: "expo" },
    ]);
    expect(call).toHaveBeenLastCalledWith("app", "push_tokens_for", {
      users: ["u1"],
    });
    expect(await devices.prune(["a", "b"]).orThrow()).toBe(2);
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
    expect(notifications.requestPermissionsAsync).toHaveBeenCalledTimes(1);
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
    expect(unregister).toHaveBeenCalledTimes(1);
  });
});

describe("expoPush", () => {
  it("sends in chunks of 100 and prunes unregistered tokens from tickets", async () => {
    const pruned: string[][] = [];
    const devices = createPushDevices({
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
    });
    expect(prune).toHaveBeenCalledWith(["b"]);
  });

  it("throws on an HTTP error", async () => {
    const { fetch } = expoFetch(() => null, 500);
    await expect(expoPush({ fetch }).send(["a"], {})).rejects.toThrow(
      "Expo Push API send answered 500",
    );
  });
});

describe("expoPushChannel", () => {
  const message: NotificationMessage = {
    deliveryId: "dl1",
    channel: "push",
    attempts: 1,
    userId: "u1",
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
    },
    text: { title: "Ada commented", body: "Looks good" },
  };

  const devicesWith = (
    tokens: readonly { token: string; provider: string }[],
  ) =>
    createPushDevices({
      transport: transport(() =>
        tokens.map((t) => ({ userId: "u1", platform: "ios", ...t })),
      ).transport,
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
    expect(send).toHaveBeenCalledWith(["a"], {
      title: "Ada commented",
      body: "Looks good",
      sound: "default",
      data: {
        notificationId: "n1",
        type: "comment.created",
        actionPath: "/posts/1",
      },
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
    expect(push.send).toHaveBeenLastCalledWith(["a"], { title: "custom" });
  });
});

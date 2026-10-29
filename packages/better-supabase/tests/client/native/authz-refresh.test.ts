import { describe, expect, it, vi } from "vitest";

import type { AuthzRefreshChannel } from "../../../src/client/authz-refresh.ts";
import type {
  AppStateLike,
  NativeAuthzRefreshClient,
} from "../../../src/client/native/index.ts";

import { startNativeAuthzRefresh } from "../../../src/client/native/index.ts";

const base64url = (value: unknown): string =>
  btoa(JSON.stringify(value))
    .replaceAll("+", "-")
    .replaceAll("/", "_")
    .replace(/[=]+$/u, "");

const token = (version: number): string =>
  `${base64url({ alg: "ES256" })}.${base64url({ sub: "u1", authz_ver: version })}.sig`;

function fakeAppState(initial = "active") {
  const listeners = new Set<(state: string) => void>();

  const state: {
    currentState: string;
    addEventListener: AppStateLike["addEventListener"];
    set(next: string): void;
  } = {
    currentState: initial,
    addEventListener(_type, listener) {
      listeners.add(listener);

      return { remove: () => listeners.delete(listener) };
    },
    set(next) {
      this.currentState = next;

      for (const listener of listeners) {
        listener(next);
      }
    },
  };

  return state;
}

function fakeClient(options: { live: number; tokenVersion: number }) {
  const handlers: ((message: { payload?: unknown }) => void)[] = [];
  const order: string[] = [];
  let version = options.tokenVersion;
  const joins = vi.fn();
  const unsubscribe = vi.fn(async () => "ok");

  const refreshSession = vi.fn(async () => {
    order.push("refresh");
    version = options.live;

    return {};
  });

  const rpc = vi.fn(
    async (
      _fn: "caller_authz_version",
    ): Promise<{ data: unknown; error: unknown }> => ({
      data: options.live,
      error: null,
    }),
  );

  const channel: AuthzRefreshChannel = {
    on(_type, _filter, callback) {
      handlers.push(callback);

      return channel;
    },
    subscribe(callback) {
      joins();
      callback?.("SUBSCRIBED");

      return channel;
    },
    unsubscribe,
  };

  const client: NativeAuthzRefreshClient = {
    channel: () => channel,
    rpc,
    auth: {
      refreshSession,
      getSession: async () => ({
        data: { session: { access_token: token(version) } },
      }),
    },
  };

  const send = (payload: unknown): void => {
    for (const handler of handlers) {
      handler({ payload });
    }
  };

  return { client, order, joins, unsubscribe, refreshSession, rpc, send };
}

const settle = () =>
  new Promise((resolve) => {
    setTimeout(resolve, 10);
  });

describe("startNativeAuthzRefresh", () => {
  it("refreshes on a newer broadcast, then runs onChange and reconnects PowerSync", async () => {
    const fake = fakeClient({ live: 1, tokenVersion: 1 });
    const appState = fakeAppState();

    const stop = startNativeAuthzRefresh({
      client: fake.client,
      userId: "u1",
      appState,
      onChange: () => fake.order.push("change"),
      powersync: {
        reconnect: async () => {
          fake.order.push("reconnect");
        },
      },
    });

    await settle();
    expect(fake.refreshSession).not.toHaveBeenCalled();

    fake.send({ user_id: "u1", version: 2 });
    fake.send({ user_id: "u1", version: 2 });
    await settle();

    expect(fake.order).toEqual(["refresh", "change", "reconnect"]);

    stop();
    expect(fake.unsubscribe).toHaveBeenCalledOnce();
  });

  it("skips a broadcast the token already carries", async () => {
    const fake = fakeClient({ live: 5, tokenVersion: 5 });

    const stop = startNativeAuthzRefresh({
      client: fake.client,
      userId: "u1",
      appState: fakeAppState(),
    });

    fake.send({ version: 5 });
    await settle();
    expect(fake.refreshSession).not.toHaveBeenCalled();

    stop();
  });

  it("drops the channel in the background and catches up once on return", async () => {
    const fake = fakeClient({ live: 3, tokenVersion: 3 });
    const appState = fakeAppState();
    const onChange = vi.fn();

    const stop = startNativeAuthzRefresh({
      client: fake.client,
      userId: "u1",
      appState,
      onChange,
    });

    await settle();
    expect(fake.joins).toHaveBeenCalledOnce();

    appState.set("background");
    expect(fake.unsubscribe).toHaveBeenCalledOnce();

    // A role changed while the app was away; no broadcast reached it.
    fake.rpc.mockResolvedValue({ data: "4", error: null });
    appState.set("active");
    await settle();

    expect(fake.joins).toHaveBeenCalledTimes(2);
    expect(fake.rpc).toHaveBeenCalledTimes(2);
    expect(fake.refreshSession).toHaveBeenCalledOnce();
    expect(onChange).toHaveBeenCalledOnce();

    stop();
  });

  it("starts in the background without subscribing", async () => {
    const fake = fakeClient({ live: 1, tokenVersion: 1 });

    const stop = startNativeAuthzRefresh({
      client: fake.client,
      userId: "u1",
      appState: fakeAppState("background"),
    });

    await settle();
    expect(fake.joins).not.toHaveBeenCalled();

    stop();
  });

  it("asks a custom source for the live version on return", async () => {
    const fake = fakeClient({ live: 1, tokenVersion: 1 });
    const appState = fakeAppState("background");
    const current = vi.fn(async () => 2);

    const stop = startNativeAuthzRefresh({
      client: fake.client,
      userId: "u1",
      appState,
      source: { current, subscribe: () => () => undefined },
    });

    appState.set("active");
    await settle();

    expect(current).toHaveBeenCalledOnce();
    expect(fake.joins).not.toHaveBeenCalled();
    expect(fake.refreshSession).toHaveBeenCalledOnce();

    stop();
  });

  it("reports a failed refresh", async () => {
    const fake = fakeClient({ live: 1, tokenVersion: 1 });
    fake.refreshSession.mockRejectedValueOnce(new Error("offline"));
    const onError = vi.fn();

    const stop = startNativeAuthzRefresh({
      client: fake.client,
      userId: "u1",
      appState: fakeAppState(),
      onError,
    });

    fake.send({ version: 2 });
    await settle();
    expect(onError).toHaveBeenCalledWith(new Error("offline"));

    stop();
  });
});

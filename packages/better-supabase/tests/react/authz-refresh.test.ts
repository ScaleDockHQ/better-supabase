import { describe, expect, it, vi } from "vitest";

import type {
  AuthzRefreshChannel,
  AuthzRefreshClient,
} from "../../src/react/authz-refresh.ts";

import { startAuthzRefresh } from "../../src/react/authz-refresh.ts";

function fakeClient(live?: number, event = "changed") {
  const handlers: ((message: { payload?: unknown }) => void)[] = [];
  const topics: string[] = [];
  const refreshSession = vi.fn(async () => ({}));
  const unsubscribe = vi.fn(async () => "ok");

  const rpc = vi.fn(async (_fn: "caller_authz_version") => ({
    data: live === undefined ? null : String(live),
    error: null,
  }));

  const channel: AuthzRefreshChannel = {
    on(_type, filter, callback) {
      expect(filter.event).toBe(event);
      handlers.push(callback);

      return channel;
    },
    subscribe(callback) {
      callback?.("SUBSCRIBED");

      return channel;
    },
    unsubscribe,
  };

  const client: AuthzRefreshClient = {
    channel(topic, options) {
      expect(options.config.private).toBe(true);
      topics.push(topic);

      return channel;
    },
    auth: { refreshSession },
    ...(live === undefined ? {} : { rpc }),
  };

  const send = (payload: unknown): void => {
    for (const handler of handlers) {
      handler({ payload });
    }
  };

  return { client, topics, refreshSession, unsubscribe, rpc, send };
}

const settle = () =>
  new Promise((resolve) => {
    setTimeout(resolve, 10);
  });

describe("startAuthzRefresh", () => {
  it("refreshes once per new version and tells the other tabs", async () => {
    const fake = fakeClient();
    const onChange = vi.fn();
    const other = new BroadcastChannel("test:authz-1");
    const posted: unknown[] = [];
    other.addEventListener("message", (event) => posted.push(event.data));

    const stop = startAuthzRefresh({
      client: fake.client,
      userId: "u1",
      channel: "test:authz-1",
      onChange,
    });

    expect(fake.topics).toEqual(["authz:u1"]);
    fake.send({ user_id: "u1", version: "2" });
    fake.send({ user_id: "u1", version: 2 });
    fake.send({ user_id: "u1", version: 1 });
    await settle();

    expect(fake.refreshSession).toHaveBeenCalledOnce();
    expect(onChange).toHaveBeenCalledOnce();
    expect(posted).toEqual([
      { type: "better-supabase:authz", userId: "u1", version: 2 },
    ]);

    stop();
    other.close();
    expect(fake.unsubscribe).toHaveBeenCalledOnce();
  });

  it("runs onChange without a refresh when another tab refreshed", async () => {
    const fake = fakeClient();
    const onChange = vi.fn();
    const other = new BroadcastChannel("test:authz-2");

    const stop = startAuthzRefresh({
      client: fake.client,
      userId: "u1",
      channel: "test:authz-2",
      onChange,
    });

    for (const userId of ["u2", "u1"]) {
      const message = { type: "better-supabase:authz", userId, version: 5 };
      // oxlint-disable-next-line unicorn/require-post-message-target-origin -- BroadcastChannel.postMessage takes no target origin (1 finding).
      other.postMessage(message);
    }

    await settle();
    fake.send({ user_id: "u1", version: 5 });
    await settle();

    expect(onChange).toHaveBeenCalledOnce();
    expect(fake.refreshSession).not.toHaveBeenCalled();

    stop();
    other.close();
  });

  it("waits in a hidden tab until it becomes visible", async () => {
    const fake = fakeClient();
    const onChange = vi.fn();

    const visibility: { visibilityState: DocumentVisibilityState } = {
      visibilityState: "hidden",
    };

    const doc = Object.assign(new EventTarget(), visibility);

    vi.stubGlobal("document", doc);

    const stop = startAuthzRefresh({
      client: fake.client,
      userId: "u1",
      channel: false,
      onChange,
    });

    fake.send({ version: 7 });
    await settle();
    expect(fake.refreshSession).not.toHaveBeenCalled();

    doc.visibilityState = "visible";
    doc.dispatchEvent(new Event("visibilitychange"));
    await settle();
    expect(fake.refreshSession).toHaveBeenCalledOnce();
    expect(onChange).toHaveBeenCalledOnce();

    stop();
    vi.unstubAllGlobals();
  });

  it("reports a failed refresh", async () => {
    const fake = fakeClient();
    fake.refreshSession.mockRejectedValueOnce(new Error("offline"));
    const onError = vi.fn();

    const stop = startAuthzRefresh({
      client: fake.client,
      userId: "u1",
      channel: false,
      onChange: vi.fn(),
      onError,
    });

    fake.send({ version: 3 });
    fake.send({ version: "x" });
    await settle();

    expect(onError).toHaveBeenCalledWith(new Error("offline"));

    stop();
  });

  it("catches up on join when the live version is ahead of the token", async () => {
    const fake = fakeClient(4);
    const onChange = vi.fn();

    const stop = startAuthzRefresh({
      client: fake.client,
      userId: "u1",
      channel: false,
      tokenVersion: () => 3,
      onChange,
    });

    await settle();
    expect(fake.rpc).toHaveBeenCalledWith("caller_authz_version");
    expect(fake.refreshSession).toHaveBeenCalledOnce();
    expect(onChange).toHaveBeenCalledOnce();

    stop();
  });

  it("does not refresh on join when the token is current or has no version", async () => {
    for (const tokenVersion of [4, null]) {
      const fake = fakeClient(4);

      const stop = startAuthzRefresh({
        client: fake.client,
        userId: "u1",
        channel: false,
        tokenVersion: () => tokenVersion,
        onChange: vi.fn(),
      });

      await settle();
      expect(fake.refreshSession).not.toHaveBeenCalled();
      stop();
    }
  });

  it("listens on a custom topic and event", async () => {
    const fake = fakeClient(undefined, "authz");

    const stop = startAuthzRefresh({
      client: fake.client,
      userId: "u1",
      channel: false,
      topic: (userId) => `acl:${userId}`,
      event: "authz",
      onChange: vi.fn(),
    });

    fake.send({ version: 2 });
    await settle();
    expect(fake.topics).toEqual(["acl:u1"]);
    expect(fake.refreshSession).toHaveBeenCalledOnce();

    stop();
  });

  it("follows a custom version source", async () => {
    const listeners: ((version: number) => void)[] = [];
    const fake = fakeClient();

    const stop = startAuthzRefresh({
      client: fake.client,
      userId: "u1",
      channel: false,
      tokenVersion: () => 1,
      source: {
        current: async () => 1,
        subscribe(listener) {
          listeners.push(listener);

          return () => undefined;
        },
      },
      onChange: vi.fn(),
    });

    for (const listener of listeners) {
      listener(1);
      listener(2);
    }

    await settle();
    expect(fake.topics).toEqual([]);
    expect(fake.refreshSession).toHaveBeenCalledOnce();

    stop();
  });
});

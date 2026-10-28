import { describe, expect, it, vi } from "vitest";

import type { AuthzVersionClient } from "../../src/server/authz-versions.ts";

import { AUTHZ_TOPIC, authzUserTopic } from "../../src/core/authz-topic.ts";
import { subscribeAuthzVersions } from "../../src/server/authz-versions.ts";

function fakeClient(status = "SUBSCRIBED") {
  const handlers: ((message: { payload?: unknown }) => void)[] = [];
  const unsubscribe = vi.fn(async () => "ok");
  const joins: { topic: string; private: boolean; event?: string }[] = [];

  const client: AuthzVersionClient = {
    channel(topic, options) {
      const join: { topic: string; private: boolean; event?: string } = {
        topic,
        private: options.config.private,
      };

      joins.push(join);

      const channel = {
        on(
          _type: "broadcast",
          filter: { readonly event: string },
          callback: (message: { payload?: unknown }) => void,
        ) {
          join.event = filter.event;
          handlers.push(callback);

          return channel;
        },
        subscribe(callback?: (status: string, error?: Error) => void) {
          queueMicrotask(() => callback?.(status));

          return channel;
        },
        unsubscribe,
      };

      return channel;
    },
  };

  return {
    client,
    joins,
    unsubscribe,
    send: (payload: unknown) => {
      for (const handler of handlers) {
        handler({ payload });
      }
    },
  };
}

const options = { topic: "versions", event: "changed", userIdKey: "user_id" };

describe("subscribeAuthzVersions", () => {
  it("evicts the user named in each message on a private channel", async () => {
    const fake = fakeClient();
    const versions = { evict: vi.fn<(userId: string) => void>() };

    const subscription = subscribeAuthzVersions({
      ...options,
      client: fake.client,
      versions,
    });

    await subscription.ready;
    fake.send({ user_id: "u1", version: 3 });

    expect(fake.joins).toEqual([
      { topic: "versions", private: true, event: "changed" },
    ]);
    expect(versions.evict).toHaveBeenCalledWith("u1");

    await subscription.close();
    expect(fake.unsubscribe).toHaveBeenCalledOnce();
  });

  it("defaults to the sessions module topic and reads a per-user topic", async () => {
    const shared = fakeClient();
    const versions = { evict: vi.fn<(userId: string) => void>() };
    const first = subscribeAuthzVersions({ client: shared.client, versions });
    await first.ready;
    shared.send({ user_id: "u1", version: 2 });

    expect(shared.joins).toEqual([
      { topic: AUTHZ_TOPIC, private: true, event: "changed" },
    ]);
    expect(versions.evict).toHaveBeenLastCalledWith("u1");
    await first.close();

    const own = fakeClient();

    const second = subscribeAuthzVersions({
      client: own.client,
      topic: authzUserTopic("u2"),
      versions,
    });

    await second.ready;
    own.send({ version: 4 });

    expect(versions.evict).toHaveBeenLastCalledWith("u2");
    await second.close();
  });

  it("joins once per cache", () => {
    const fake = fakeClient();
    const versions = { evict: vi.fn<(userId: string) => void>() };

    const first = subscribeAuthzVersions({
      ...options,
      client: fake.client,
      versions,
    });

    const second = subscribeAuthzVersions({
      ...options,
      client: fake.client,
      versions,
    });

    expect(second).toBe(first);
    expect(fake.joins).toHaveLength(1);
  });

  it("reports a message without the user id key and a failed join", async () => {
    const fake = fakeClient("CHANNEL_ERROR");
    const onError = vi.fn<(error: Error) => void>();
    const versions = { evict: vi.fn<(userId: string) => void>() };

    const subscription = subscribeAuthzVersions({
      ...options,
      client: fake.client,
      versions,
      onError,
    });

    fake.send({ id: "u1" });
    await expect(subscription.ready).rejects.toThrow("channel_error");

    expect(versions.evict).not.toHaveBeenCalled();
    expect(onError).toHaveBeenCalledTimes(2);
    expect(
      subscribeAuthzVersions({ ...options, client: fake.client, versions }),
    ).not.toBe(subscription);
  });
});

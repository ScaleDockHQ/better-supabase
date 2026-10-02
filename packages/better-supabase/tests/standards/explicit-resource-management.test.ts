import { describe, expect, it, vi } from "vitest";

import { createPostgres } from "../../src/postgres/index.ts";
import { defineTopic, type RealtimeClient } from "../../src/realtime/index.ts";
import { fakePgPool } from "../fixtures/fake-pg-pool.ts";
import { topics } from "../fixtures/generated-camel.ts";

// TC39 explicit resource management: `using` calls [Symbol.dispose] and
// `await using` calls [Symbol.asyncDispose] when the block exits, in reverse
// order and also when the block throws.

function fakeRealtime() {
  const removed: unknown[] = [];
  const channel = {
    on: () => channel,
    subscribe: (callback: (status: string) => void) => {
      queueMicrotask(() => callback("SUBSCRIBED"));
      return channel;
    },
    httpSend: async () => ({ success: true as const }),
  };
  const client = {
    channel: vi.fn(() => channel),
    removeChannel: vi.fn(async (value: unknown) => {
      removed.push(value);
      return "ok" as const;
    }),
    realtime: { setAuth: async () => undefined },
  };
  return { client: client as unknown as RealtimeClient, removed };
}

const notifications = defineTopic(topics.notifications, { events: {} });

describe("explicit resource management", () => {
  it("`await using` a Postgres client ends its pool", async () => {
    const fake = fakePgPool();
    {
      await using pg = createPostgres({ pool: fake.pool });
      expect(typeof pg[Symbol.asyncDispose]).toBe("function");
      await pg.admin.queryRaw("select 1");
    }
    expect(fake.ended).toBe(1);
    expect(fake.released).toBe(fake.connections);
  });

  it("`await using` disposes even when the block throws", async () => {
    const fake = fakePgPool();
    await expect(
      (async () => {
        await using pg = createPostgres({ pool: fake.pool });
        await pg.admin.queryRaw("select 1");
        throw new Error("boom");
      })(),
    ).rejects.toThrow("boom");
    expect(fake.ended).toBe(1);
  });

  it("`using` and `await using` both leave a topic subscription", async () => {
    const { client, removed } = fakeRealtime();
    {
      using sync = notifications.subscribe(
        client,
        { orgId: "o1", userId: "u1" },
        {},
      );
      await sync.ready;
    }
    {
      await using async = notifications.subscribe(
        client,
        { orgId: "o1", userId: "u2" },
        {},
      );
      await async.ready;
    }
    await new Promise((resolve) => setTimeout(resolve, 0));
    expect(removed).toHaveLength(2);
  });

  it("disposes in reverse order inside an AsyncDisposableStack", async () => {
    const order: string[] = [];
    const first = fakePgPool();
    const second = fakePgPool();
    first.pool.end = async () => void order.push("first");
    second.pool.end = async () => void order.push("second");
    {
      await using stack = new AsyncDisposableStack();
      stack.use(createPostgres({ pool: first.pool }));
      stack.use(createPostgres({ pool: second.pool }));
    }
    expect(order).toEqual(["second", "first"]);
  });
});

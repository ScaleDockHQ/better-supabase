import { describe, expect, it } from "vitest";

import type { BlockTransport } from "../../../src/core/block-transport.ts";

import {
  postgresPublisher,
  postgresSubscriber,
} from "../../../src/streams/resumable/index.ts";

function kvTransport(): { transport: BlockTransport; calls: string[] } {
  const values = new Map<string, string>();
  const calls: string[] = [];

  const transport: BlockTransport = {
    async call(_schema, fn, args) {
      calls.push(fn);
      const key = String(args["key"]);

      if (fn === "stream_kv_get") {
        return values.get(key) ?? null;
      }

      if (fn === "stream_kv_set") {
        values.set(key, String(args["value"]));

        return "OK";
      }

      if (fn === "stream_kv_incr") {
        const current = values.get(key);

        if (current !== undefined && !/^-?\d+$/.test(current)) {
          throw new Error("ERR value is not an integer or out of range");
        }

        const next = Number(current ?? "0") + 1;
        values.set(key, String(next));

        return next;
      }

      return 0;
    },
  };

  return { transport, calls };
}

describe("postgresPublisher", () => {
  it("implements get, set and incr, and incr on DONE raises Redis's text", async () => {
    const { transport } = kvTransport();
    const publisher = postgresPublisher({ transport });

    expect(await publisher.get("k")).toBeNull();
    expect(await publisher.incr("k")).toBe(1);
    expect(await publisher.incr("k")).toBe(2);

    await publisher.set("k", "DONE", { EX: 60 });
    expect(await publisher.get("k")).toBe("DONE");
    await expect(publisher.incr("k")).rejects.toThrow(
      "ERR value is not an integer or out of range",
    );
  });

  it("publishes through stream_kv_publish", async () => {
    const { transport, calls } = kvTransport();
    await postgresPublisher({ transport }).publish("c", "m");

    expect(calls).toEqual(["stream_kv_publish"]);
  });
});

describe("postgresSubscriber", () => {
  it("resolves subscribe after the join and delivers broadcast messages", async () => {
    const handlers: ((payload: { payload?: unknown }) => void)[] = [];
    const removed: unknown[] = [];

    const channel = {
      on: (
        _type: "broadcast",
        _filter: unknown,
        cb: (p: { payload?: unknown }) => void,
      ) => {
        handlers.push(cb);

        return channel;
      },
      subscribe: (cb?: (status: string) => void) => {
        queueMicrotask(() => cb?.("SUBSCRIBED"));

        return channel;
      },
    };

    const subscriber = postgresSubscriber({
      realtime: {
        channel: () => channel,
        removeChannel: async (value) => {
          removed.push(value);
        },
      },
    });

    const received: string[] = [];
    await subscriber.subscribe("chunk:1", (message) => received.push(message));
    handlers[0]?.({ payload: { message: "hello" } });
    expect(received).toEqual(["hello"]);

    await subscriber.unsubscribe("chunk:1");
    expect(removed).toHaveLength(1);
  });
});

describe("postgresSubscriber, remaining paths", () => {
  const fakeRealtime = (statuses: string[]) => {
    const removed: unknown[] = [];
    const handlers: ((payload: { payload?: unknown }) => void)[] = [];

    const channel = {
      on: (
        _type: "broadcast",
        _filter: unknown,
        cb: (p: { payload?: unknown }) => void,
      ) => {
        handlers.push(cb);

        return channel;
      },
      subscribe: (cb?: (status: string, error?: Error) => void) => {
        queueMicrotask(() => {
          for (const status of statuses) {
            cb?.(
              status,
              status === "SUBSCRIBED" ? undefined : new Error(status),
            );
          }
        });

        return channel;
      },
    };

    return {
      removed,
      handlers,
      realtime: {
        channel: () => channel,
        removeChannel: async (value: unknown) => {
          removed.push(value);
        },
      },
    };
  };

  it("connects, joins again by removing the old channel, and ignores odd payloads", async () => {
    const fake = fakeRealtime(["JOINING", "SUBSCRIBED"]);

    const subscriber = postgresSubscriber({
      realtime: fake.realtime,
      topic: "s",
    });

    const received: string[] = [];

    await subscriber.connect();
    await subscriber.subscribe("c", (message) => received.push(message));
    await subscriber.subscribe("c", (message) => received.push(message));

    for (const payload of [undefined, null, {}, { message: 5 }]) {
      fake.handlers[0]?.({ payload });
    }

    await subscriber.unsubscribe("unknown");

    expect(fake.removed).toHaveLength(1);
    expect(received).toEqual([]);
  });

  it("rejects when the join fails", async () => {
    for (const status of ["CHANNEL_ERROR", "TIMED_OUT", "CLOSED"]) {
      const subscriber = postgresSubscriber({
        realtime: fakeRealtime([status]).realtime,
      });

      await expect(subscriber.subscribe("c", () => 0)).rejects.toThrow(status);
    }
  });
});

describe("postgresPublisher, remaining paths", () => {
  it("connects, and refuses a transport error and a non-number counter", async () => {
    const { transport } = kvTransport();
    const publisher = postgresPublisher({ transport });

    await publisher.connect();

    const failing = postgresPublisher({
      transport: { call: () => Promise.reject(new Error("db down")) },
    });

    await expect(failing.get("k")).rejects.toThrow(/.+/);
  });
});

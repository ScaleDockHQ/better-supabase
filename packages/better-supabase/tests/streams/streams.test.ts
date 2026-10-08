import type { SupabaseClient } from "@supabase/supabase-js";

import { describe, expect, it, vi } from "vitest";

import {
  postgresStreamStore,
  resumeFromStore,
  teeToStore,
} from "../../src/streams/index.ts";
import { redisStreamStore } from "../../src/streams/redis/index.ts";
import { testStreamStore } from "../../src/testing/index.ts";
import { fakeRedis, fakeStreamsTransport } from "./fakes.ts";

const fromChunks = (chunks: readonly string[]): ReadableStream<string> =>
  new ReadableStream<string>({
    start(controller) {
      for (const chunk of chunks) controller.enqueue(chunk);
      controller.close();
    },
  });

async function text(stream: ReadableStream<string>): Promise<string> {
  let out = "";
  for await (const chunk of stream) out += chunk;
  return out;
}

describe("postgresStreamStore", () => {
  it("passes the conformance kit", async () => {
    const { transport } = fakeStreamsTransport();
    const report = await testStreamStore(
      postgresStreamStore({ transport, pollMs: 5 }),
    );
    expect(report.checks.every((check) => check.ok)).toBe(true);
  });

  it("sends the module's arguments", async () => {
    const { transport, calls } = fakeStreamsTransport();
    const store = postgresStreamStore({ transport, wake: "poll" });
    await store
      .open("s1", { owner: "u1", tenant: "t1", kind: "chat", ttl: 60 })
      .orThrow();
    await store.purge({ olderThan: "2 hours" }).orThrow();
    expect(calls).toEqual([
      {
        fn: "stream_open",
        args: {
          stream_id: "s1",
          owner: "u1",
          tenant: "t1",
          kind: "chat",
          ttl: "60 seconds",
          wake: false,
        },
      },
      { fn: "purge_streams", args: { older_than: "2 hours" } },
    ]);
  });

  it("wakes readers on the stream's private topic", async () => {
    const { transport } = fakeStreamsTransport();
    let onWake: (() => void) | undefined;
    const channel = {
      on: vi.fn((_type: string, _filter: object, callback: () => void) => {
        onWake = callback;
        return channel;
      }),
      subscribe: vi.fn(() => channel),
    };
    const realtime = {
      channel: vi.fn(() => channel),
      removeChannel: vi.fn(async () => "ok"),
    };
    const store = postgresStreamStore({
      transport,
      // SAFETY: the fake implements the channel calls the store makes.
      realtime: realtime as unknown as Pick<
        SupabaseClient,
        "channel" | "removeChannel"
      >,
      pollMs: 60_000,
    });
    await store.open("s2").orThrow();
    const reading = text(store.read("s2"));
    await vi.waitFor(() => {
      expect(onWake).toBeDefined();
    });
    await store.append("s2", 0, ["hi"]).orThrow();
    await store.close("s2").orThrow();
    onWake?.();
    expect(await reading).toBe("hi");
    expect(realtime.channel).toHaveBeenCalledWith("stream:s2", {
      config: { private: true },
    });
    expect(realtime.removeChannel).toHaveBeenCalledTimes(1);
  });

  it("errors the read with the DbError", async () => {
    const store = postgresStreamStore({
      transport: {
        call: async () => {
          throw Object.assign(new Error("denied"), { code: "42501" });
        },
      },
    });
    await expect(text(store.read("s"))).rejects.toMatchObject({
      kind: "forbidden",
    });
  });

  it("stops reading on abort", async () => {
    const { transport } = fakeStreamsTransport();
    const store = postgresStreamStore({ transport, pollMs: 60_000 });
    await store.open("s3").orThrow();
    const abort = new AbortController();
    const reading = text(store.read("s3", 0, { signal: abort.signal }));
    abort.abort();
    expect(await reading).toBe("");
  });
});

describe("redisStreamStore", () => {
  it("passes the conformance kit with and without a subscriber", async () => {
    const { client, subscriber } = fakeRedis();
    for (const store of [
      redisStreamStore({ client, pollMs: 5 }),
      redisStreamStore({ client, subscriber, prefix: "app:s" }),
    ]) {
      const report = await testStreamStore(store);
      expect(report.checks.every((check) => check.ok)).toBe(true);
    }
  });

  it("publishes a wake-up per batch and parses intervals", async () => {
    const { client, published } = fakeRedis();
    const store = redisStreamStore({ client });
    expect(await store.open("r", { ttl: "2 hours" }).orThrow()).toBe(true);
    await store.append("r", 0, ["a"]).orThrow();
    await store.append("r", 0, ["a"]).orThrow();
    expect(published).toEqual(["bs:stream:r append"]);
    const bad = await store.open("x", { ttl: "soon" });
    expect(bad.ok ? undefined : bad.error.kind).toBe("invalid_input");
  });
});

describe("teeToStore", () => {
  it("passes the stream through and stores every chunk at its index", async () => {
    const { transport } = fakeStreamsTransport();
    const store = postgresStreamStore({ transport, pollMs: 5 });
    const { stream, persisted } = teeToStore(
      store,
      "t1",
      fromChunks(["a", "b", "c"]),
      { flushMs: 1, kind: "chat" },
    );
    expect(await text(stream)).toBe("abc");
    expect(await persisted.orThrow()).toBe(3);
    expect(await text(store.read("t1", 1))).toBe("bc");
    expect((await store.status("t1").orThrow())?.closed).toBe(true);
  });

  it("flushes on size and calls onCancel once", async () => {
    const { client } = fakeRedis();
    const store = redisStreamStore({ client });
    await store.open("t2").orThrow();
    await store.cancel("t2").orThrow();
    const onCancel = vi.fn();
    const { stream, persisted } = teeToStore(
      store,
      "t2",
      fromChunks(["xx", "yy", "zz"]),
      { flushBytes: 2, onCancel },
    );
    await text(stream);
    expect(await persisted.orThrow()).toBe(3);
    expect(onCancel).toHaveBeenCalledTimes(1);
  });

  it("keeps storing after the live client disconnects", async () => {
    const { client } = fakeRedis();
    const store = redisStreamStore({ client });
    const { stream, persisted } = teeToStore(
      store,
      "t3",
      fromChunks(["1", "2"]),
    );
    await stream.cancel();
    expect(await persisted.orThrow()).toBe(2);
    expect(await text(store.read("t3"))).toBe("12");
  });

  it("returns the store's error and the source's error", async () => {
    const { client } = fakeRedis();
    const store = redisStreamStore({ client });
    await store.open("t4").orThrow();
    await store.close("t4").orThrow();
    const closed = teeToStore(store, "t4", fromChunks(["a"]));
    await text(closed.stream);
    const result = await closed.persisted;
    expect(result.ok ? undefined : result.error.hint).toBe("STREAM_CLOSED");

    const failing = new ReadableStream<string>({
      start(controller) {
        controller.enqueue("a");
        controller.error(new Error("model failed"));
      },
    });
    const broken = teeToStore(store, "t5", failing);
    await text(broken.stream).catch(() => undefined);
    const outcome = await broken.persisted;
    expect(outcome.ok).toBe(false);
    expect((await store.status("t5").orThrow())?.closed).toBe(true);

    const refused = redisStreamStore({
      client: {
        ...client,
        hSetNX: async () => {
          throw new Error("down");
        },
      },
    });
    const notOpened = teeToStore(refused, "t6", fromChunks(["a"]));
    expect((await notOpened.persisted).ok).toBe(false);
  });
});

describe("resumeFromStore", () => {
  it("resumes from an index and says when there is nothing", async () => {
    const { client } = fakeRedis();
    const store = redisStreamStore({ client });
    expect(await resumeFromStore(store, "none").orThrow()).toBeUndefined();
    await store.open("r1").orThrow();
    await store.append("r1", 0, ["a", "b"]).orThrow();
    await store.close("r1").orThrow();
    const rest = await resumeFromStore(store, "r1", { fromIdx: 1 }).orThrow();
    expect(rest && (await text(rest))).toBe("b");
    expect(
      await resumeFromStore(store, "r1", {
        fromIdx: 2,
        signal: new AbortController().signal,
      }).orThrow(),
    ).toBeUndefined();
  });
});

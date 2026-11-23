import { describe, expect, it, vi } from "vitest";

import { postgresCacheHandler } from "../../src/cache-postgres/next.ts";
import { dbError } from "../../src/core/errors.ts";
import { err } from "../../src/core/result.ts";
import { memoryStore } from "./memory-store.ts";

function entry(text: string, tags: string[], timestamp = Date.now()) {
  return {
    value: new Response(text).body!,
    tags,
    stale: 30,
    timestamp,
    expire: 3600,
    revalidate: 300,
  };
}

async function read(stream: ReadableStream<Uint8Array>): Promise<string> {
  return new Response(stream).text();
}

describe("postgresCacheHandler", () => {
  it("returns what set stored, as a new stream on every get", async () => {
    const handler = postgresCacheHandler({ client: memoryStore() });

    await handler.set("k", Promise.resolve(entry("hello", ["bsb:orders"])));

    const first = await handler.get("k", []);
    const second = await handler.get("k", []);

    expect(first && (await read(first.value))).toBe("hello");
    expect(second && (await read(second.value))).toBe("hello");
    expect(first?.tags).toEqual(["bsb:orders"]);
    expect(first?.revalidate).toBe(300);
  });

  it("misses after the tag is expired and stays a hit for other tags", async () => {
    const handler = postgresCacheHandler({ client: memoryStore() });
    const past = Date.now() - 1000;

    await handler.set("a", Promise.resolve(entry("a", ["bsb:orders"], past)));
    await handler.set("b", Promise.resolve(entry("b", ["bsb:users"], past)));
    await handler.updateTags(["bsb:orders"]);

    expect(await handler.get("a", [])).toBeUndefined();
    expect(await handler.get("b", [])).toBeDefined();
    expect(await handler.getExpiration(["bsb:orders"])).toBeGreaterThan(0);
    expect(await handler.getExpiration(["bsb:none"])).toBe(0);
  });

  it("renders a missing entry once across instances and serves the others its entry", async () => {
    const store = memoryStore();
    const first = postgresCacheHandler({ client: store });
    const second = postgresCacheHandler({ client: store, wait: 500 });

    expect(await first.get("k", [])).toBeUndefined();

    const waiting = second.get("k", []);

    await first.set("k", Promise.resolve(entry("filled", [])));

    const served = await waiting;

    expect(served && (await read(served.value))).toBe("filled");
  });

  it("renders itself once the wait runs out", async () => {
    const store = memoryStore();
    const first = postgresCacheHandler({ client: store });
    const second = postgresCacheHandler({ client: store, wait: 50 });

    await first.get("k", []);

    expect(await second.get("k", [])).toBeUndefined();
  });

  it("releases the lease after set, so the next miss renders at once", async () => {
    const store = memoryStore();
    const lease = vi.spyOn(store, "lease");
    const handler = postgresCacheHandler({ client: store, wait: 10_000 });

    await handler.get("k", []);
    await handler.set("k", Promise.resolve({ ...entry("x", []), expire: 0 }));

    const started = Date.now();

    await handler.get("k", []);

    expect(Date.now() - started).toBeLessThan(1000);
    expect(lease.mock.results).toHaveLength(2);
    expect(await lease.mock.results[1]?.value).toMatchObject({ data: true });
  });

  it("checks soft tags on get", async () => {
    const handler = postgresCacheHandler({ client: memoryStore() });

    await handler.set("k", Promise.resolve(entry("x", [], Date.now() - 1000)));
    await handler.updateTags(["_N_T_/layout"]);

    expect(await handler.get("k", ["_N_T_/layout"])).toBeUndefined();
  });

  it("serves a stale-tag entry once more with revalidate -1", async () => {
    const handler = postgresCacheHandler({ client: memoryStore() });

    await handler.set(
      "k",
      Promise.resolve(entry("x", ["t"], Date.now() - 1000)),
    );
    await handler.updateTags(["t"], { expire: 60 });

    const hit = await handler.get("k", []);

    expect(hit?.revalidate).toBe(-1);
  });

  it("does not store an expire 0 entry in production", async () => {
    const store = memoryStore();
    const handler = postgresCacheHandler({ client: store });

    await handler.set("k", Promise.resolve({ ...entry("x", []), expire: 0 }));

    expect(store.entries.size).toBe(0);
  });

  it("turns store errors into misses and reports them", async () => {
    const store = memoryStore();
    const failure = dbError("unexpected", "down");
    const onError = vi.fn();

    const handler = postgresCacheHandler({
      client: { ...store, lookup: () => Promise.resolve(err(failure)) },
      onError,
    });

    expect(await handler.get("k", [])).toBeUndefined();
    expect(onError).toHaveBeenCalledWith(failure);
  });

  it("throws when an invalidation cannot be written", async () => {
    const store = memoryStore();

    const handler = postgresCacheHandler({
      client: {
        ...store,
        markTags: () => Promise.resolve(err(dbError("unexpected", "down"))),
      },
    });

    await expect(handler.updateTags(["t"])).rejects.toThrow("down");
  });
});

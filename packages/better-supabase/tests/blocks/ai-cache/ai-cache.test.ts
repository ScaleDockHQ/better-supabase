import { describe, expect, it } from "vitest";

import type { BlockTransport } from "../../../src/core/block-transport.ts";

import { cacheKey, createAiCache } from "../../../src/blocks/ai-cache/index.ts";

const AT = "2026-01-01T00:00:00Z";

const entryRow = (overrides: Record<string, unknown> = {}) => ({
  key: "k1",
  organization_id: "o1",
  kind: "generate",
  model: "openai/gpt-5",
  value: { text: "hi" },
  hits: 2,
  created_at: AT,
  last_hit_at: null,
  expires_at: new Date("2026-01-02T00:00:00Z"),
  ...overrides,
});

type Handler = (args: Record<string, unknown>) => unknown;

function fakeTransport(handlers: Record<string, Handler>) {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const transport: BlockTransport = {
    call: (_schema, fn, args) => {
      calls.push({ fn, args });
      const handler = handlers[fn];
      if (!handler) return Promise.reject(new Error(`unexpected ${fn}`));
      return Promise.resolve(handler(args));
    },
  };
  return { transport, calls };
}

describe("cacheKey", () => {
  it("ignores key order and undefined fields", async () => {
    const a = await cacheKey({ model: "m", prompt: "p", extra: undefined });
    const b = await cacheKey({ prompt: "p", model: "m" });
    expect(a).toBe(b);
    expect(a).toMatch(/^[0-9a-f]{64}$/);
  });

  it("counts bytes, dates and URLs by content", async () => {
    const parts = (byte: number) => ({
      data: new Uint8Array([1, byte]),
      at: new Date(AT),
      url: new URL("https://example.com/a"),
      list: [() => 1, null],
    });
    expect(await cacheKey(parts(2))).toBe(await cacheKey(parts(2)));
    expect(await cacheKey(parts(2))).not.toBe(await cacheKey(parts(3)));
    expect(await cacheKey(undefined)).toBe(await cacheKey(null));
  });
});

describe("createAiCache", () => {
  it("reads an entry and maps a miss to undefined", async () => {
    const { transport } = fakeTransport({
      ai_cache_get: (args) =>
        args["key"] === "k1"
          ? entryRow()
          : args["key"] === "odd"
            ? entryRow({ kind: "bogus", hits: null, organization_id: null })
            : null,
    });
    const cache = createAiCache({ transport });
    const hit = await cache.get<{ text: string }>("k1").orThrow();
    expect(hit?.value.text).toBe("hi");
    expect(hit?.hits).toBe(2);
    expect(hit?.expiresAt.toString()).toBe("2026-01-02T00:00:00Z");
    expect(await cache.get("missing").orThrow()).toBeUndefined();
    const odd = await cache.get("odd").orThrow();
    expect(odd).toMatchObject({
      kind: "other",
      hits: 0,
      organizationId: undefined,
    });
  });

  it("stores with a whole-second TTL and returns the entry without its value", async () => {
    const { transport, calls } = fakeTransport({
      ai_cache_set: () => entryRow({ value: undefined }),
    });
    const cache = createAiCache({ transport });
    const entry = await cache
      .set(
        "k1",
        { text: "hi" },
        { ttl: 0.2, organizationId: "o1", kind: "stream", model: "m" },
      )
      .orThrow();
    expect(calls[0]?.args).toEqual({
      key: "k1",
      value: { text: "hi" },
      ttl: 1,
      tenant: "o1",
      kind: "stream",
      model: "m",
    });
    expect("value" in entry).toBe(false);
  });

  it("deletes, clears and purges", async () => {
    const { transport, calls } = fakeTransport({
      ai_cache_delete: (args) =>
        args["key"] === "k1" ? 1 : args["key"] ? 0 : 4,
      purge_ai_cache: () => 3,
    });
    const cache = createAiCache({ transport });
    expect(await cache.delete("k1").orThrow()).toBe(true);
    expect(await cache.delete("k2").orThrow()).toBe(false);
    expect(await cache.clear({ organizationId: "o1" }).orThrow()).toBe(4);
    expect(await cache.purge().orThrow()).toBe(3);
    expect(
      await cache.purgeJob({ batch: 10 })(
        undefined,
        undefined as never,
        new AbortController().signal,
      ),
    ).toBe(3);
    expect(calls.at(-1)?.args).toEqual({ batch: 10 });
  });
});

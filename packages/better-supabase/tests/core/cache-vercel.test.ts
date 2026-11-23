import { describe, expect, it, vi } from "vitest";

import {
  encodeCacheTag,
  vercelCdnCache,
  vercelRuntimeCacheAdapter,
} from "../../src/core/cache-vercel.ts";
import { testCacheAdapter } from "../../src/testing/index.ts";

function fakeCache() {
  return {
    get: vi.fn<(key: string) => Promise<unknown>>(() => Promise.resolve(null)),
    set: vi.fn<
      (
        key: string,
        value: unknown,
        options?: { name?: string; tags?: string[]; ttl?: number },
      ) => Promise<void>
    >(() => Promise.resolve()),
    expireTag: vi.fn<(tag: string | string[]) => Promise<void>>(() =>
      Promise.resolve(),
    ),
  };
}

describe("encodeCacheTag", () => {
  it("keeps the tags the library writes", () => {
    expect(encodeCacheTag("bsb:orders")).toBe("bsb:orders");
    expect(encodeCacheTag("bsb:orders@acme")).toBe("bsb:orders@acme");
    expect(encodeCacheTag("bsb:orders@*")).toBe("bsb:orders@*");
    expect(encodeCacheTag("bsb:orders:018f-ab")).toBe("bsb:orders:018f-ab");
  });

  it("removes the comma of a composite key and every URL delimiter", () => {
    expect(encodeCacheTag("bsb:links:1,2")).toBe("bsb:links:1~2c2");
    expect(encodeCacheTag("bsb:a:x&y#z?w%v+u t")).not.toMatch(/[,&#?% +]/u);
  });

  it("keeps two different tags different", () => {
    expect(encodeCacheTag("a~2c")).not.toBe(encodeCacheTag("a,"));
    expect(encodeCacheTag("é")).toBe("~c3~a9");
  });

  it("drops a tag over 256 bytes", () => {
    expect(encodeCacheTag(`bsb:t:${"x".repeat(251)}`)).toBeUndefined();
    expect(encodeCacheTag(`bsb:t:${"x".repeat(250)}`)).toBeDefined();
  });
});

describe("vercelRuntimeCacheAdapter", () => {
  it("expires the tags of a mutation, once each", async () => {
    const cache = fakeCache();
    const adapter = vercelRuntimeCacheAdapter(() => cache);

    await adapter.invalidate({
      table: "orders",
      tables: ["orders", "orders"],
      ids: ["1", "a,b"],
      tenant: "acme",
    });

    expect(cache.expireTag).toHaveBeenCalledExactlyOnceWith([
      "bsb:orders",
      "bsb:orders@acme",
      "bsb:orders:1",
      "bsb:orders:a~2cb",
    ]);
  });

  it("splits a large mutation into calls of 16 tags", async () => {
    const cache = fakeCache();
    const adapter = vercelRuntimeCacheAdapter(() => cache);
    const ids = Array.from({ length: 40 }, (_, index) => String(index));

    await adapter.invalidate({ table: "orders", tables: ["orders"], ids });

    const sizes = cache.expireTag.mock.calls.map(([tags]) => tags.length);
    expect(sizes).toEqual([16, 16, 10]);
  });

  it("opens the cache on first use, in its namespace", async () => {
    const cache = fakeCache();

    const getCache = vi.fn<(options?: { namespace?: string }) => typeof cache>(
      () => cache,
    );

    const adapter = vercelRuntimeCacheAdapter(getCache, { namespace: "app" });
    expect(getCache).not.toHaveBeenCalled();

    await adapter.get("k");
    await adapter.get("k");

    expect(getCache).toHaveBeenCalledExactlyOnceWith({ namespace: "app" });
    expect(cache.get).toHaveBeenCalledWith("k");
  });

  it("stores a value with its tags encoded and its ttl", async () => {
    const cache = fakeCache();
    const adapter = vercelRuntimeCacheAdapter(() => cache);

    await adapter.set("orders:list", [1], {
      ttl: 60,
      tags: ["bsb:orders", "bsb:links:1,2"],
    });

    await adapter.set("plain", 1);

    expect(cache.set).toHaveBeenNthCalledWith(1, "orders:list", [1], {
      ttl: 60,
      tags: ["bsb:orders", "bsb:links:1~2c2"],
    });

    expect(cache.set).toHaveBeenNthCalledWith(2, "plain", 1, {});
  });

  it("deletes an entry by key, and does nothing on a cache without delete", async () => {
    const remove = vi.fn<(key: string) => Promise<void>>(() =>
      Promise.resolve(),
    );

    const withDelete = vercelRuntimeCacheAdapter(() => ({
      ...fakeCache(),
      delete: remove,
    }));

    await withDelete.delete("orders:list");
    await vercelRuntimeCacheAdapter(() => fakeCache()).delete("orders:list");

    expect(remove).toHaveBeenCalledExactlyOnceWith("orders:list");
  });

  it("passes the conformance kit", async () => {
    const report = await testCacheAdapter(
      vercelRuntimeCacheAdapter(() => fakeCache()),
    );

    expect(report.checks.filter((check) => !check.ok)).toEqual([]);
  });
});

describe("vercelCdnCache", () => {
  const sdk = () => ({
    addCacheTag: vi.fn<(tag: string | string[]) => Promise<void>>(() =>
      Promise.resolve(),
    ),
    invalidateByTag: vi.fn<(tag: string | string[]) => Promise<void>>(() =>
      Promise.resolve(),
    ),
  });

  it("invalidates by tag", async () => {
    const functions = sdk();
    const cdn = vercelCdnCache(functions);

    await cdn.invalidate({ table: "orders", tables: ["orders"], ids: ["9"] });

    expect(functions.invalidateByTag).toHaveBeenCalledWith([
      "bsb:orders",
      "bsb:orders@*",
      "bsb:orders:9",
    ]);
  });

  it("tags a response with encoded tags, at most 128", async () => {
    const functions = sdk();
    const cdn = vercelCdnCache(functions);

    await cdn.tag("bsb:links:1,2", "bsb:links");

    expect(functions.addCacheTag).toHaveBeenCalledWith([
      "bsb:links:1~2c2",
      "bsb:links",
    ]);

    await cdn.tag(
      ...Array.from({ length: 200 }, (_, index) => `bsb:t:${String(index)}`),
    );

    expect(functions.addCacheTag.mock.calls.at(-1)?.[0]).toHaveLength(128);
  });

  it("does not call addCacheTag without a usable tag", async () => {
    const functions = sdk();
    await vercelCdnCache(functions).tag(`bsb:t:${"x".repeat(300)}`);
    expect(functions.addCacheTag).not.toHaveBeenCalled();
  });

  it("passes the conformance kit", async () => {
    const report = await testCacheAdapter(vercelCdnCache(sdk()));
    expect(report.checks.filter((check) => !check.ok)).toEqual([]);
  });
});

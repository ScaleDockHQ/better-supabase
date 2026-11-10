import { describe, expect, it, vi } from "vitest";

import { createVersionCache } from "../../src/server/authz-versions.ts";

describe("createVersionCache", () => {
  it("drops the least recently used user past maxEntries", async () => {
    const cache = createVersionCache({ maxStaleMs: 1000, maxEntries: 2 });

    await cache.seed("a", 1);
    await cache.seed("b", 2);
    expect(await cache.get("a")).toBe(1);

    await cache.seed("c", 3);

    expect(await cache.get("b")).toBeUndefined();
    expect(await cache.get("a")).toBe(1);
    expect(await cache.get("c")).toBe(3);
  });

  it("keeps the higher version a slow bootstrap seeds", async () => {
    const cache = createVersionCache({ maxStaleMs: 1000 });

    await cache.seed("u", 5);
    await cache.seed("u", 3);

    expect(await cache.get("u")).toBe(5);
  });

  it("forgets a version after maxStaleMs", async () => {
    vi.useFakeTimers();

    const cache = createVersionCache({ maxStaleMs: 100 });

    await cache.seed("u", 1);
    vi.advanceTimersByTime(101);

    expect(await cache.get("u")).toBeUndefined();
    vi.useRealTimers();
  });

  it("reads the shared store on a local miss and clears it on evict", async () => {
    const data = new Map<string, number>([["u", 7]]);

    const store = {
      get: (id: string) => data.get(id),
      set: (id: string, v: number) => void data.set(id, v),
      delete: (id: string) => void data.delete(id),
    };

    const cache = createVersionCache({ store, maxStaleMs: 1000 });

    expect(await cache.get("u")).toBe(7);

    await cache.evict("u");

    expect(data.has("u")).toBe(false);
    expect(await cache.get("u")).toBeUndefined();
  });
});

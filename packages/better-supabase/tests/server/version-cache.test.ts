import { describe, expect, it, vi } from "vitest";

import type {
  VersionStore,
  VersionStoreEntry,
} from "../../src/server/authz-versions.ts";

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
    const data = new Map<string, VersionStoreEntry>([
      ["u", { version: 7, at: Date.now() }],
    ]);

    const cache = createVersionCache({
      store: mapStore(data),
      maxStaleMs: 1000,
    });

    expect(await cache.get("u")).toBe(7);

    await cache.evict("u");

    expect(data.has("u")).toBe(false);
    expect(await cache.get("u")).toBeUndefined();
  });

  it("counts maxStaleMs from the read time in a store that never expires", async () => {
    vi.useFakeTimers();

    const data = new Map<string, VersionStoreEntry>();

    const writer = createVersionCache({
      store: mapStore(data),
      maxStaleMs: 100,
    });

    await writer.seed("u", 1);
    vi.advanceTimersByTime(60);

    const reader = createVersionCache({
      store: mapStore(data),
      maxStaleMs: 100,
    });

    expect(await reader.get("u")).toBe(1);

    vi.advanceTimersByTime(60);

    expect(await reader.get("u")).toBeUndefined();
    expect(await reader.get("u")).toBeUndefined();
    expect(data.get("u")?.version).toBe(1);
    vi.useRealTimers();
  });

  it("passes the read time to the store and keeps it for a slow lower seed", async () => {
    vi.useFakeTimers();

    const data = new Map<string, VersionStoreEntry>();

    const cache = createVersionCache({
      store: mapStore(data),
      maxStaleMs: 1000,
    });

    const first = Date.now();

    await cache.seed("u", 5);
    vi.advanceTimersByTime(200);
    await cache.seed("u", 3);

    expect(data.get("u")).toEqual({ version: 5, at: first });

    await cache.seed("u", 6);

    expect(data.get("u")).toEqual({ version: 6, at: first + 200 });
    vi.useRealTimers();
  });

  it("treats a bare number from an old store as a miss", async () => {
    const store = {
      get: () => 7 as unknown as VersionStoreEntry,
      set: () => undefined,
      delete: () => undefined,
    };

    const cache = createVersionCache({ store, maxStaleMs: 1000 });

    expect(await cache.get("u")).toBeUndefined();
  });
});

function mapStore(data: Map<string, VersionStoreEntry>): VersionStore {
  return {
    get: (id) => data.get(id),
    set: (id, version, at) => void data.set(id, { version, at }),
    delete: (id) => void data.delete(id),
  };
}

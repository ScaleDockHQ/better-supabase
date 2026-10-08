import { afterEach, describe, expect, it, vi } from "vitest";

import { persistQueryCache } from "../../../src/client/native/persist.ts";

function fakeAsyncStorage() {
  const map = new Map<string, string>();
  const writes: string[] = [];
  return {
    map,
    writes,
    storage: {
      getItem: (key: string) => Promise.resolve(map.get(key) ?? null),
      setItem: (key: string, value: string) => {
        writes.push(value);
        map.set(key, value);
        return Promise.resolve();
      },
      removeItem: (key: string) => {
        map.delete(key);
        return Promise.resolve();
      },
    },
  };
}

describe("persistQueryCache", () => {
  afterEach(() => {
    vi.useRealTimers();
  });

  it("throttles writes to the latest cache and restores it", async () => {
    vi.useFakeTimers();
    const fake = fakeAsyncStorage();
    const persister = persistQueryCache<{ n: number }>(fake.storage, {
      throttleMs: 100,
    });
    await persister.persistClient({ n: 1 });
    await persister.persistClient({ n: 2 });
    expect(fake.writes).toEqual([]);
    await vi.advanceTimersByTimeAsync(100);
    expect(fake.writes).toEqual([JSON.stringify({ n: 2 })]);
    expect(await persister.restoreClient()).toEqual({ n: 2 });
  });

  it("restores nothing when the entry is missing or corrupt", async () => {
    const fake = fakeAsyncStorage();
    const persister = persistQueryCache(fake.storage, { key: "cache" });
    expect(await persister.restoreClient()).toBeUndefined();
    fake.map.set("cache", "{not json");
    expect(await persister.restoreClient()).toBeUndefined();
  });

  it("drops a pending write when the cache is removed", async () => {
    vi.useFakeTimers();
    const fake = fakeAsyncStorage();
    fake.map.set("better-supabase.query-cache", "{}");
    const persister = persistQueryCache(fake.storage);
    await persister.persistClient({ n: 1 });
    await persister.removeClient();
    await vi.advanceTimersByTimeAsync(2000);
    expect(fake.writes).toEqual([]);
    expect(fake.map.size).toBe(0);
  });
});

import { describe, expect, it, vi } from "vitest";

import type {
  KeptCall,
  KeptSkip,
  KeptStore,
} from "../../src/core/kept-cache.ts";

import {
  KEPT_LIMITS,
  createKeptCache,
  keptKey,
  keptVersionOf,
  memoryKeptStore,
} from "../../src/core/kept-cache.ts";

function clock(start = 1_000_000): {
  now: () => number;
  tick: (ms: number) => void;
} {
  let at = start;

  return {
    now: () => at,
    tick: (ms) => {
      at += ms;
    },
  };
}

function call<T>(
  fill: () => Promise<T>,
  overrides: Partial<KeptCall<T>> = {},
): KeptCall<T> {
  return {
    name: "open-invoices",
    key: "kept:a",
    tags: ["bsb:invoices"],
    revalidate: 60,
    expire: 3600,
    fill,
    ...overrides,
  };
}

describe("keptKey", () => {
  it("is the same for arguments with keys in another order", async () => {
    const one = await keptKey({
      name: "f",
      args: [{ a: 1, b: 2 }],
      share: "u1",
      version: "v",
    });

    const two = await keptKey({
      name: "f",
      args: [{ b: 2, a: 1 }],
      share: "u1",
      version: "v",
    });

    expect(one).toBe(two);
    expect(one).toMatch(/^kept:[0-9a-f]{64}$/);
  });

  it("differs by name, arguments, share key and version", async () => {
    const base = { name: "f", args: [1], share: "u1", version: "v" };

    const keys = await Promise.all([
      keptKey(base),
      keptKey({ ...base, name: "g" }),
      keptKey({ ...base, args: [2] }),
      keptKey({ ...base, share: "u2" }),
      keptKey({ ...base, version: "w" }),
    ]);

    expect(new Set(keys).size).toBe(5);
  });

  it("hashes the schema metadata into a short version", async () => {
    const one = await keptVersionOf({ tables: { a: 1 } });

    expect(one).toHaveLength(16);
    expect(await keptVersionOf({ tables: { a: 2 } })).not.toBe(one);
  });
});

describe("createKeptCache", () => {
  it("fills on a miss and serves the stored value until it is stale", async () => {
    const time = clock();
    const store = memoryKeptStore({ now: time.now });
    const cache = createKeptCache({ store, now: time.now });
    const fill = vi.fn(() => Promise.resolve({ ok: true, data: [1] }));

    expect(await cache.serve(call(fill))).toMatchObject({
      outcome: "miss",
      value: { ok: true, data: [1] },
    });

    time.tick(59_000);

    expect(await cache.serve(call(fill))).toEqual({
      outcome: "hit",
      value: { ok: true, data: [1] },
    });
    expect(fill).toHaveBeenCalledOnce();
  });

  it("returns what JSON gives back on a miss, as a hit would", async () => {
    const cache = createKeptCache({ store: memoryKeptStore() });
    const at = new Date(0);

    const served = await cache.serve(
      call(() => Promise.resolve({ at, gone: undefined })),
    );

    expect(served.value).toEqual({ at: at.toISOString() });
  });

  it("serves a stale entry and refreshes it in the background", async () => {
    const time = clock();

    const cache = createKeptCache({
      store: memoryKeptStore({ now: time.now }),
      now: time.now,
    });

    let value = 1;
    const background: Promise<unknown>[] = [];

    await cache.serve(call(() => Promise.resolve(value)));
    time.tick(61_000);
    value = 2;

    const stale = await cache.serve(
      call(() => Promise.resolve(value), {
        background: (work) => background.push(work),
      }),
    );

    expect(stale).toEqual({ outcome: "stale", value: 1 });
    expect(background).toHaveLength(1);
    await Promise.all(background);

    expect(await cache.serve(call(() => Promise.resolve(3)))).toEqual({
      outcome: "hit",
      value: 2,
    });
  });

  it("misses once a tag of the entry expires", async () => {
    const time = clock();

    const cache = createKeptCache({
      store: memoryKeptStore({ now: time.now }),
      now: time.now,
    });

    await cache.serve(call(() => Promise.resolve(1)));
    time.tick(1);
    await cache.adapter.invalidate({
      table: "invoices",
      tables: ["invoices"],
      ids: [],
    });
    time.tick(1);

    expect(await cache.serve(call(() => Promise.resolve(2)))).toMatchObject({
      outcome: "miss",
      value: 2,
    });
  });

  it.each([
    [
      "error",
      () => Promise.resolve({ ok: false, error: { code: "unknown" } }),
      {},
    ],
    ["value", () => Promise.resolve({ n: 10n }), {}],
    ["size", () => Promise.resolve("x".repeat(KEPT_LIMITS.bytes)), {}],
    [
      "tags",
      () => Promise.resolve(1),
      {
        tags: Array.from(
          { length: KEPT_LIMITS.tags + 1 },
          (_, i) => `t${String(i)}`,
        ),
      },
    ],
    ["tag", () => Promise.resolve(1), { tags: ["x".repeat(300)] }],
  ] as const)(
    "skips the store for reason %s",
    async (reason, fill, overrides) => {
      const store = memoryKeptStore();
      const set = vi.spyOn(store, "set");
      const skips: KeptSkip[] = [];

      const cache = createKeptCache({
        store,
        onSkip: (skip) => skips.push(skip),
      });

      const served = await cache.serve(call<unknown>(fill, overrides));

      expect(served.outcome).toBe("miss");
      expect(set).not.toHaveBeenCalled();
      expect(skips).toEqual([
        expect.objectContaining({
          name: "open-invoices",
          key: "kept:a",
          reason,
        }),
      ]);
    },
  );

  it("reads through and reports when the store fails", async () => {
    const errors: unknown[] = [];

    const broken: KeptStore = {
      get: () => Promise.reject(new Error("down")),
      set: () => Promise.reject(new Error("down")),
      expireTags: () => Promise.resolve(),
    };

    const cache = createKeptCache({
      store: broken,
      onError: (e) => errors.push(e),
    });

    expect(await cache.serve(call(() => Promise.resolve(1)))).toMatchObject({
      outcome: "miss",
      value: 1,
    });
    expect(errors).toHaveLength(2);
  });

  it("ignores a stored value that is not an envelope", async () => {
    const store = memoryKeptStore();
    await store.set("kept:a", "junk", { ttl: 60, tags: [] });
    const cache = createKeptCache({ store });

    expect((await cache.serve(call(() => Promise.resolve(1)))).outcome).toBe(
      "miss",
    );
  });
});

describe("memoryKeptStore", () => {
  it("drops an entry after its ttl and after delete", async () => {
    const time = clock();
    const store = memoryKeptStore({ now: time.now });

    await store.set("a", 1, { ttl: 10, tags: [] });
    await store.set("b", 2, { ttl: 10, tags: [] });
    await store.delete?.("b");
    expect(await store.get("a")).toBe(1);
    expect(await store.get("b")).toBeUndefined();

    time.tick(10_000);
    expect(await store.get("a")).toBeUndefined();
  });

  it("keeps an entry stored after its tag expired", async () => {
    const time = clock();
    const store = memoryKeptStore({ now: time.now });

    await store.expireTags(["t"]);
    time.tick(1);
    await store.set("a", 1, { ttl: 10, tags: ["t"] });

    expect(await store.get("a")).toBe(1);
  });
});

describe("createKeptCache fills once", () => {
  it("runs one fill for concurrent misses in one process", async () => {
    const cache = createKeptCache({ store: memoryKeptStore() });
    const fill = vi.fn(() => Promise.resolve({ total: 1 }));

    const [first, second] = await Promise.all([
      cache.serve(call(fill)),
      cache.serve(call(fill)),
    ]);

    expect(fill).toHaveBeenCalledOnce();
    expect(first.outcome).toBe("miss");
    expect(second).toEqual({ value: { total: 1 }, outcome: "wait" });
  });

  it("lets another instance wait for the fill that holds the lease", async () => {
    const store = memoryKeptStore();
    const one = createKeptCache({ store });
    const two = createKeptCache({ store, wait: 1000 });

    let finish = (_value: number): void => {};

    const slow = vi.fn(
      () =>
        new Promise<number>((resolve) => {
          finish = resolve;
        }),
    );

    const fast = vi.fn(() => Promise.resolve(2));
    const filling = one.serve(call(slow));

    await vi.waitFor(() => {
      expect(slow).toHaveBeenCalledWith();
    });

    const waiting = two.serve(call(fast));

    finish(1);

    expect(await filling).toMatchObject({ value: 1, outcome: "miss" });
    expect(await waiting).toEqual({ value: 1, outcome: "wait" });
    expect(fast).not.toHaveBeenCalled();
  });

  it("fills itself once the wait runs out", async () => {
    const store = memoryKeptStore();
    await store.lease?.("kept:a", "someone else", 60_000);

    const cache = createKeptCache({ store, wait: 50 });
    const served = await cache.serve(call(() => Promise.resolve(3)));

    expect(served).toMatchObject({ value: 3, outcome: "miss" });
  });

  it("releases the lease after the fill", async () => {
    const store = memoryKeptStore();
    const cache = createKeptCache({ store });

    await cache.serve(call(() => Promise.resolve(1), { key: "kept:b" }));

    expect(await store.lease?.("kept:b", "next", 1000)).toBe(true);
  });

  it("starts one refresh for a stale entry and none while another holds the lease", async () => {
    const time = clock();
    const store = memoryKeptStore({ now: time.now });
    const cache = createKeptCache({ store, now: time.now });
    const background: Promise<unknown>[] = [];

    await cache.serve(call(() => Promise.resolve(1)));
    time.tick(61_000);

    const refill = vi.fn(() => Promise.resolve(2));

    const stale = call(refill, {
      background: (pending) => {
        background.push(pending);
      },
    });

    await Promise.all([cache.serve(stale), cache.serve(stale)]);
    await Promise.all(background);

    expect(background).toHaveLength(1);
    expect(refill).toHaveBeenCalledOnce();

    time.tick(61_000);
    await store.lease?.("kept:a", "another instance", 60_000);
    await cache.serve(stale);
    await Promise.all(background);

    expect(refill).toHaveBeenCalledOnce();
  });

  it("fills when the lease call fails, and reports it", async () => {
    const errors: unknown[] = [];

    const store: KeptStore = {
      ...memoryKeptStore(),
      lease: () => Promise.reject(new Error("lock down")),
    };

    const cache = createKeptCache({
      store,
      onError: (error) => errors.push(error),
    });

    expect(await cache.serve(call(() => Promise.resolve(4)))).toMatchObject({
      value: 4,
      outcome: "miss",
    });
    expect(errors).toHaveLength(1);
  });
});

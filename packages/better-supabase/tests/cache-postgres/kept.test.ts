import { describe, expect, it } from "vitest";

import { postgresKeptStore } from "../../src/cache-postgres/kept.ts";
import { dbError } from "../../src/core/errors.ts";
import { createKeptCache } from "../../src/core/kept-cache.ts";
import { err } from "../../src/core/result.ts";
import { memoryStore } from "./memory-store.ts";

describe("postgresKeptStore", () => {
  it("stores the envelope as JSON bytes with its tags and ttl", async () => {
    const tables = memoryStore();
    const store = postgresKeptStore({ client: tables });

    await store.set(
      "kept:a",
      { storedAt: 1, revalidate: 60, value: [1] },
      { ttl: 600, tags: ["bsb:invoices"] },
    );

    const entry = tables.entries.get("kept:a");
    expect(entry?.tags).toEqual(["bsb:invoices"]);
    expect(entry?.meta).toEqual({ kind: "kept" });
    expect((entry?.expiresAt ?? 0) - (entry?.storedAt ?? 0)).toBe(600_000);
    expect(await store.get("kept:a")).toEqual({
      storedAt: 1,
      revalidate: 60,
      value: [1],
    });
  });

  it("misses after a write to a table and after delete", async () => {
    const tables = memoryStore();

    const cache = createKeptCache({
      store: postgresKeptStore({ client: tables }),
    });

    const call = {
      name: "f",
      key: "kept:a",
      tags: ["bsb:invoices"],
      revalidate: 60,
      expire: 600,
    };

    await cache.serve({ ...call, fill: () => Promise.resolve(1) });
    await new Promise((resolve) => {
      setTimeout(resolve, 2);
    });
    await cache.adapter.invalidate({
      table: "invoices",
      tables: ["invoices"],
      ids: [],
    });
    await new Promise((resolve) => {
      setTimeout(resolve, 2);
    });

    expect(
      await cache.serve({ ...call, fill: () => Promise.resolve(2) }),
    ).toMatchObject({ outcome: "miss", value: 2 });

    await postgresKeptStore({ client: tables }).delete?.("kept:a");
    expect(tables.entries.has("kept:a")).toBe(false);
  });

  it("throws the store's error, so the cache reads through", async () => {
    const tables = memoryStore();

    const failing = {
      ...tables,
      lookup: () => Promise.resolve(err(dbError("network", "down"))),
    };

    await expect(
      postgresKeptStore({ client: failing }).get("kept:a"),
    ).rejects.toThrow("down");
  });
});

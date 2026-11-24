import { describe, expect, it } from "vitest";

import { postgresCacheNames } from "../../src/cache-postgres/names.ts";
import { sqlBackend } from "../../src/cache-postgres/sql-backend.ts";
import { MISSING } from "../../src/cache-postgres/store-core.ts";

const recording = (answer: (text: string) => unknown[] | Error) => {
  const calls: { text: string; params: unknown[] }[] = [];

  return {
    calls,
    client: {
      queryRaw<T>(text: string, params: unknown[] = []): Promise<T[]> {
        calls.push({ text, params });
        const result = answer(text);

        // SAFETY: the test answers each query with rows of the type it asks for.
        return result instanceof Error
          ? Promise.reject(result)
          : Promise.resolve(result as T[]);
      },
    },
  };
};

const missing = Object.assign(new Error("no such function"), { code: "42883" });

describe("sqlBackend", () => {
  const names = postgresCacheNames({ schema: "cache" });

  it("reads and writes entries, tags and leases with parameters", async () => {
    const { calls, client } = recording((text) =>
      text.includes("as won") ? [{ won: true }] : [{ key: "k" }],
    );

    const backend = sqlBackend(client, names);

    expect(await backend.selectEntry("k")).toEqual({ key: "k" });
    expect(await backend.callGet("k", ["t"], 1)).toEqual({ key: "k" });
    await backend.upsertEntry({
      key: "k",
      value: "v",
      tags: ["t"],
      stored_at: 1,
      expires_at: 2,
      path: null,
      meta: { a: 1 },
    });
    await backend.deleteWhere("path", "/p");
    await backend.deleteExpired(3);
    expect(await backend.selectTags(["t"])).toEqual([{ key: "k" }]);
    await backend.upsertTags([{ tag: "t", stale_at: 1, expired_at: 2 }]);
    expect(await backend.callMarkTags(["t"], "stale", 0, 4)).toBe(true);
    expect(await backend.callLease("k", "h", 10, 5)).toBe(true);
    await backend.deleteLease("k", "h");

    expect(calls.map((call) => call.text.split("\n")[0])).toEqual([
      `select key, value, tags, stored_at, expires_at, path, meta from "cache"."bsb_cache_entries" where key = $1`,
      `select * from "cache"."bsb_cache_get"($1::text, $2::text[], $3::bigint)`,
      `insert into "cache"."bsb_cache_entries" (key, value, tags, stored_at, expires_at, path, meta)`,
      `delete from "cache"."bsb_cache_entries" where "path" = $1`,
      `delete from "cache"."bsb_cache_entries" where expires_at < $1`,
      `select * from "cache"."bsb_cache_tags" where tag = any($1::text[])`,
      `insert into "cache"."bsb_cache_tags" (tag, stale_at, expired_at)`,
      `select "cache"."bsb_cache_mark_tags"($1::text[], $2::text, $3::bigint, $4::bigint)`,
      `select "cache"."bsb_cache_lease"($1::text, $2::text, $3::bigint, $4::bigint) as won`,
      `delete from "cache"."bsb_cache_leases" where key = $1 and holder = $2`,
    ]);
    expect(calls[2]?.params.at(-1)).toBe('{"a":1}');
    expect(calls[6]?.params).toEqual([["t"], [1], [2]]);
  });

  it("reports a missing function and rethrows other errors", async () => {
    const absent = sqlBackend(recording(() => missing).client, names);

    expect(await absent.callGet("k", [], 1)).toBe(MISSING);
    expect(await absent.callMarkTags(["t"], "expire", 1, 1)).toBe(MISSING);
    expect(await absent.callLease("k", "h", 1, 1)).toBe(MISSING);

    const broken = sqlBackend(recording(() => new Error("down")).client, names);

    await expect(broken.callGet("k", [], 1)).rejects.toThrow("down");
    await expect(broken.callMarkTags(["t"], "delay", 1, 1)).rejects.toThrow(
      "down",
    );
    await expect(broken.callLease("k", "h", 1, 1)).rejects.toThrow("down");

    const lost = sqlBackend(recording(() => []).client, names);

    expect(await lost.callLease("k", "h", 1, 1)).toBe(false);
  });
});

import { createClient } from "@supabase/supabase-js";
import { Pool } from "pg";
import { afterAll, beforeAll, describe, expect, it } from "vitest";

import type { PostgresCacheStore } from "../../src/cache-postgres/store.ts";

import { postgresCacheHandler } from "../../src/cache-postgres/next.ts";
import { postgresCacheSql } from "../../src/cache-postgres/sql.ts";
import { postgresCacheStore } from "../../src/cache-postgres/store.ts";
import { dbUrl, reachable } from "./block-session.ts";
import { stackUrl } from "./stack-env.ts";

const live = await reachable();

const secretKey =
  process.env["SUPABASE_SECRET_KEY"] ??
  "sb_secret_N7UND0UgjKTVK-Uodkm0Hg_xSvEMPvz";

const suffix = Math.random().toString(36).slice(2, 8);

const names = {
  entriesTable: `bsb_test_cache_entries_${suffix}`,
  tagsTable: `bsb_test_cache_tags_${suffix}`,
  leasesTable: `bsb_test_cache_leases_${suffix}`,
  functionPrefix: `bsb_test_cache_${suffix}`,
};

const entry = (key: string, tags: string[], storedAt: number) => ({
  key,
  value: new Uint8Array([1, 2, 3]),
  tags,
  storedAt,
  expiresAt: storedAt + 3_600_000,
  meta: {},
});

describe.skipIf(!live)("cache-postgres against the local stack", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 4 });

  const sql = {
    queryRaw: async <T>(text: string, params?: unknown[]): Promise<T[]> =>
      (await pool.query(text, params)).rows as T[],
  };

  const client = createClient(stackUrl(), secretKey, {
    auth: { persistSession: false },
  });

  const stores: [string, PostgresCacheStore][] = [];

  beforeAll(async () => {
    await pool.query(postgresCacheSql(names));
    await pool.query("notify pgrst, 'reload schema'");

    // PostgREST reloads its schema cache asynchronously; a store created
    // before it knows the functions would fall back for good.
    const deadline = Date.now() + 10_000;

    while (Date.now() < deadline) {
      const probe = await client.rpc(`${names.functionPrefix}_mark_tags`, {
        p_tags: [],
      });

      if (!probe.error) {
        break;
      }

      await new Promise((resolve) => {
        setTimeout(resolve, 200);
      });
    }

    stores.push(
      ["PostgREST", postgresCacheStore({ client, ...names })],
      [
        "a pool",
        postgresCacheStore({ transport: { postgres: sql }, ...names }),
      ],
    );
  });

  afterAll(async () => {
    await pool.query(
      `drop function if exists public.${names.functionPrefix}_get(text, text[], bigint);
drop function if exists public.${names.functionPrefix}_mark_tags(text[], text, bigint, bigint);
drop function if exists public.${names.functionPrefix}_lease(text, text, bigint, bigint);
drop table if exists public.${names.entriesTable}, public.${names.tagsTable}, public.${names.leasesTable};`,
    );
    await pool.end();
  });

  it("keeps the latest delayed expiry when 50 calls mark the same tags at once", async () => {
    for (const [, store] of stores) {
      const now = Date.now();
      const tags = [`burst-${suffix}-a`, `burst-${suffix}-b`];

      const results = await Promise.all(
        Array.from({ length: 50 }, (_, index) =>
          store.markTags(index % 2 === 0 ? tags : tags.toReversed(), {
            now,
            expireSeconds: index + 1,
          }),
        ),
      );

      expect(results.every((result) => result.ok)).toBe(true);

      const states = await store.tagStates(tags);

      expect(states.ok && states.data.get(tags[0]!)?.expireAfter).toBe(
        now + 50_000,
      );
      expect(states.ok && states.data.get(tags[1]!)?.expireAfter).toBe(
        now + 50_000,
      );

      await pool.query(
        `delete from public.${names.tagsTable} where tag = any($1)`,
        [tags],
      );
    }
  });

  it("gives a lease to exactly one of 50 holders at once, and to the next after release", async () => {
    for (const [label, store] of stores) {
      const key = `lease-${suffix}-${label}`;

      const results = await Promise.all(
        Array.from({ length: 50 }, (_, index) =>
          store.lease(key, `holder-${String(index)}`, 60_000),
        ),
      );

      const winners = results.flatMap((result, index) =>
        result.ok && result.data ? [index] : [],
      );

      expect(results.every((result) => result.ok)).toBe(true);
      expect(winners).toHaveLength(1);

      const winner = `holder-${String(winners[0])}`;

      expect((await store.lease(key, winner, 60_000)).ok).toBe(true);
      expect(await store.lease(key, "late", 60_000)).toMatchObject({
        data: false,
      });

      await store.release(key, winner);

      expect(await store.lease(key, "late", 60_000)).toMatchObject({
        data: true,
      });
      await store.release(key, "late");
    }
  });

  it("never lets an immediate expiry drop a delayed one, or the other way round", async () => {
    for (const [, store] of stores) {
      const tag = `mixed-${suffix}`;
      const now = Date.now();

      await store.markTags([tag], { now, expireSeconds: 60 });
      await store.markTags([tag], { now: now + 1 });
      await store.markTags([tag], { now: now + 2, staleOnly: true });

      const states = await store.tagStates([tag]);

      expect(states.ok && states.data.get(tag)).toEqual({
        staleAt: now + 2,
        expiredAt: now + 1,
        expireAfter: now + 60_000,
      });

      await pool.query(`delete from public.${names.tagsTable} where tag = $1`, [
        tag,
      ]);
    }
  });

  it("reads a live entry in one call, and misses it once a tag expired", async () => {
    for (const [label, store] of stores) {
      const key = `entry-${suffix}-${label}`;
      const tag = `orders-${suffix}-${label}`;
      const soft = `soft-${suffix}-${label}`;
      const now = Date.now();

      expect((await store.set(entry(key, [tag], now + 0.412))).ok).toBe(true);

      const hit = await store.lookup(key, [soft], now + 1);
      expect(hit.ok && hit.data?.stale).toBe(false);
      expect(hit.ok && [...(hit.data?.entry.value ?? [])]).toEqual([1, 2, 3]);

      await store.markTags([soft], { now: now + 2, staleOnly: true });
      const stale = await store.lookup(key, [soft], now + 3);
      expect(stale.ok && stale.data?.stale).toBe(true);

      await store.markTags([tag], { now: now + 4, expireSeconds: 10 });
      const before = await store.lookup(key, [], now + 5);
      const after = await store.lookup(key, [], now + 10_005);
      expect(before.ok && before.data?.stale).toBe(true);
      expect(after.ok && after.data).toBeUndefined();

      expect((await store.delete(key)).ok).toBe(true);
      const gone = await store.get(key);
      expect(gone.ok && gone.data).toBeUndefined();
    }
  });

  it("serves an entry a second handler instance wrote, until updateTags on the first", async () => {
    const first = postgresCacheHandler({ client, ...names });

    const second = postgresCacheHandler({
      transport: { postgres: sql },
      ...names,
    });

    const tag = `page-${suffix}`;

    await first.set(
      `page-${suffix}`,
      Promise.resolve({
        value: new Blob(["<p>hi</p>"]).stream(),
        tags: [tag],
        stale: 0,
        timestamp: Date.now() - 10,
        expire: 3600,
        revalidate: 900,
      }),
    );

    const read = await second.get(`page-${suffix}`, []);
    expect(await new Response(read?.value).text()).toBe("<p>hi</p>");

    await first.updateTags([tag]);
    expect(await second.get(`page-${suffix}`, [])).toBeUndefined();
  });

  it("falls back to the tables when the functions are missing, and says so once", async () => {
    const errors: string[] = [];

    const store = postgresCacheStore({
      transport: { postgres: sql },
      ...names,
      functionPrefix: `bsb_missing_${suffix}`,
      onError: (error) => errors.push(error.message),
    });

    const now = Date.now();

    await store.set(entry(`fallback-${suffix}`, [`fb-${suffix}`], now));
    const hit = await store.lookup(`fallback-${suffix}`, [], now + 1);
    await store.markTags([`fb-${suffix}`], { now: now + 2 });
    const miss = await store.lookup(`fallback-${suffix}`, [], now + 3);

    expect(hit.ok && hit.data?.entry.key).toBe(`fallback-${suffix}`);
    expect(miss.ok && miss.data).toBeUndefined();
    expect(errors).toHaveLength(1);
  });
});

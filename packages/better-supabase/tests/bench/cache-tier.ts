/**
 * The numbers behind the shared cache tier: a `postgresCacheHandler` read on a
 * hit, a tag mark, the fills when 20 requests on two instances miss the same
 * key, and what the first request of a fresh process pays (JWKS, PostgREST,
 * pool). It creates its own tables in `public` and drops them afterwards.
 *
 *     node --env-file=../../.env.development.local tests/bench/cache-tier.ts [runs]
 */
import { createClient } from "@supabase/supabase-js";
import { Pool } from "pg";

import { postgresCacheHandler } from "../../src/cache-postgres/next.ts";
import { postgresCacheSql } from "../../src/cache-postgres/sql.ts";
import { postgresCacheStore } from "../../src/cache-postgres/store.ts";
import { format, summarize, time } from "./stats.ts";

const url = process.env["SUPABASE_URL"];
const secret = process.env["SUPABASE_SECRET_KEY"];
const dbUrl = process.env["SUPABASE_DB_URL"];
const runs = Number(process.argv[2] ?? 200);

if (!url || !secret || !dbUrl) {
  console.error("Set SUPABASE_URL, SUPABASE_SECRET_KEY and SUPABASE_DB_URL.");
  process.exit(1);
}

const tables = {
  entriesTable: "bsb_bench_cache_entries",
  tagsTable: "bsb_bench_cache_tags",
  functionPrefix: "bsb_bench_cache",
};

const firstStart = performance.now();

const first = {
  jwks: await time(() =>
    fetch(`${url}/auth/v1/.well-known/jwks.json`).then((r) => r.arrayBuffer()),
  ),
  rest: await time(() =>
    fetch(`${url}/rest/v1/`, {
      headers: { apikey: secret, authorization: `Bearer ${secret}` },
    }).then((r) => r.arrayBuffer()),
  ),
  pool: 0,
};

const pool = new Pool({ connectionString: dbUrl, max: 4 });

first.pool = await time(() => pool.query("select 1"));

const warm = {
  jwks: await time(() =>
    fetch(`${url}/auth/v1/.well-known/jwks.json`).then((r) => r.arrayBuffer()),
  ),
  rest: await time(() =>
    fetch(`${url}/rest/v1/`, {
      headers: { apikey: secret, authorization: `Bearer ${secret}` },
    }).then((r) => r.arrayBuffer()),
  ),
  pool: await time(() => pool.query("select 1")),
};

console.log(
  `first request              jwks ${first.jwks.toFixed(1)} ms  rest ${first.rest.toFixed(1)} ms  pool ${first.pool.toFixed(1)} ms  (total ${(performance.now() - firstStart).toFixed(1)} ms)`,
);

console.log(
  `second request             jwks ${warm.jwks.toFixed(1)} ms  rest ${warm.rest.toFixed(1)} ms  pool ${warm.pool.toFixed(1)} ms`,
);

await pool.query(postgresCacheSql(tables));

await pool.query("notify pgrst, 'reload schema'");

const client = createClient(url, secret, { auth: { persistSession: false } });

// PostgREST reloads its schema cache asynchronously.
for (let tries = 0; tries < 50; tries += 1) {
  const probe = await client.rpc(`${tables.functionPrefix}_mark_tags`, {
    p_tags: [],
  });

  if (!probe.error) {
    break;
  }

  await new Promise((resolve) => {
    setTimeout(resolve, 200);
  });
}

const sql = {
  queryRaw: async <T>(text: string, params?: unknown[]): Promise<T[]> =>
    (await pool.query(text, params)).rows as T[],
};

const onError = (error: { message: string }): void => {
  console.error(error.message);
};

const handlers = [
  ["PostgREST", postgresCacheHandler({ client, ...tables, onError })],
  [
    "pool",
    postgresCacheHandler({ transport: { postgres: sql }, ...tables, onError }),
  ],
] as const;

const entry = (timestamp: number) => ({
  value: new ReadableStream<Uint8Array>({
    start(controller) {
      controller.enqueue(new TextEncoder().encode("x".repeat(2048)));
      controller.close();
    },
  }),
  tags: ["bsb:t:orders", "bsb:tenant:acme"],
  stale: 30,
  timestamp,
  expire: 3600,
  revalidate: 60,
});

try {
  for (const [label, handler] of handlers) {
    await handler.set("bench:hit", Promise.resolve(entry(Date.now())));

    for (let index = 0; index < 5; index += 1) {
      await handler.get("bench:hit", ["_N_T_/orders"]);
    }

    const reads: number[] = [];

    for (let index = 0; index < runs; index += 1) {
      reads.push(
        await time(async () => {
          const found = await handler.get("bench:hit", ["_N_T_/orders"]);

          if (!found) {
            throw new Error("the bench entry was not a hit");
          }
        }),
      );
    }

    console.log(format(`cache-postgres get (hit), ${label}`, summarize(reads)));

    const marks: number[] = [];

    for (let index = 0; index < Math.min(runs, 100); index += 1) {
      marks.push(
        await time(() =>
          handler.updateTags([`bench:mark:${String(index % 4)}`]),
        ),
      );
    }

    console.log(format(`cache-postgres markTags, ${label}`, summarize(marks)));
  }

  // Two instances, ten requests each, all missing one key at once.
  const instances = [
    postgresCacheHandler({ client: postgresCacheStore({ client, ...tables }) }),
    postgresCacheHandler({ client: postgresCacheStore({ client, ...tables }) }),
  ];

  let fills = 0;

  await Promise.all(
    Array.from({ length: 20 }, async (_, index) => {
      const instance = instances[index % 2];

      if (!instance) {
        return;
      }

      const found = await instance.get("bench:miss", []);

      if (!found) {
        fills += 1;
        await new Promise((resolve) => {
          setTimeout(resolve, 50);
        });
        await instance.set("bench:miss", Promise.resolve(entry(Date.now())));
      }
    }),
  );

  console.log(
    `fills for 20 concurrent misses on 2 instances: ${String(fills)}`,
  );
} finally {
  await pool.query(
    `drop function if exists public.${tables.functionPrefix}_get(text, text[], bigint);
drop function if exists public.${tables.functionPrefix}_mark_tags(text[], text, bigint, bigint);
drop table if exists public.${tables.entriesTable}, public.${tables.tagsTable}`,
  );
  await pool.end();
}

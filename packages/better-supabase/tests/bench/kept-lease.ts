/**
 * What a `bsb.kept()` miss costs on the Runtime Cache store with no lease, with
 * its lock entry, and with `postgresKeptLease()`: four instances get five calls
 * each for one missing key at once, and the fill takes 50 ms. The Runtime Cache
 * is an in-memory stand-in, since only a deployment reaches the real one: each
 * call waits `latency` ms (5 by default), and another instance sees a write
 * `propagation` ms later (25 by default; 0 makes every read consistent). The
 * Postgres lease runs against the local database. It creates its own tables in
 * `public` and drops them afterwards.
 *
 *     node --env-file=../../.env.development.local tests/bench/kept-lease.ts [rounds] [latency] [propagation]
 */
import { Pool } from "pg";

import type { KeptStore } from "../../src/core/kept-cache.ts";

import { postgresKeptLease } from "../../src/cache-postgres/kept.ts";
import { postgresCacheSql } from "../../src/cache-postgres/sql.ts";
import { vercelRuntimeCacheAdapter } from "../../src/core/cache-vercel.ts";
import { createKeptCache } from "../../src/core/kept-cache.ts";
import { format, summarize } from "./stats.ts";

const dbUrl = process.env["SUPABASE_DB_URL"];
const rounds = Number(process.argv[2] ?? 20);
const latency = Number(process.argv[3] ?? 5);
const propagation = Number(process.argv[4] ?? 25);

if (!dbUrl) {
  console.error("Set SUPABASE_DB_URL.");
  process.exit(1);
}

const tables = {
  entriesTable: "bsb_bench_lease_entries",
  tagsTable: "bsb_bench_lease_tags",
  leasesTable: "bsb_bench_lease_leases",
  functionPrefix: "bsb_bench_lease",
};

const pool = new Pool({ connectionString: dbUrl, max: 8 });

const sql = {
  queryRaw: async <T>(text: string, params?: unknown[]): Promise<T[]> =>
    // SAFETY: each caller names the row shape its statement returns.
    (await pool.query(text, params)).rows as T[],
};

const sleep = (ms: number): Promise<void> =>
  new Promise((resolve) => {
    setTimeout(resolve, ms);
  });

/**
 * One Runtime Cache region with a replica per instance. `instance(n)` reads and
 * writes replica n; a write reaches the other replicas `propagation` ms later,
 * at once when it is 0.
 */
function runtimeCache() {
  const replicas = Array.from({ length: 4 }, () => new Map<string, unknown>());

  const write = (
    from: number,
    apply: (replica: Map<string, unknown>) => void,
  ) => {
    for (const [at, replica] of replicas.entries()) {
      if (at === from || propagation === 0) {
        apply(replica);
      } else {
        setTimeout(() => {
          apply(replica);
        }, propagation);
      }
    }
  };

  return (instance: number) => () => ({
    get: async (key: string) => {
      await sleep(latency);

      return replicas[instance]?.get(key);
    },
    set: async (key: string, value: unknown) => {
      await sleep(latency);
      write(instance, (replica) => replica.set(key, value));
    },
    delete: async (key: string) => {
      await sleep(latency);
      write(instance, (replica) => replica.delete(key));
    },
    expireTag: () => sleep(latency),
  });
}

type Mode = "no lease" | "Runtime Cache lock" | "postgresKeptLease";

const storeFor = (
  mode: Mode,
  region: ReturnType<ReturnType<typeof runtimeCache>>,
): KeptStore => {
  switch (mode) {
    case "no lease": {
      const adapter = vercelRuntimeCacheAdapter(region);

      return {
        get: async (key) => adapter.get(key),
        set: async (key, value, options) => adapter.set(key, value, options),
        expireTags: async (tags) => adapter.expireTags(tags),
      };
    }

    case "Runtime Cache lock": {
      return vercelRuntimeCacheAdapter(region);
    }

    case "postgresKeptLease": {
      return vercelRuntimeCacheAdapter(region, {
        lease: postgresKeptLease({ transport: { postgres: sql }, ...tables }),
      });
    }

    default: {
      const never: never = mode;

      return never;
    }
  }
};

async function round(mode: Mode, index: number) {
  const region = runtimeCache();
  let fills = 0;

  const fill = async () => {
    fills += 1;
    await sleep(50);

    return "value";
  };

  const call = {
    name: "bench",
    key: `bench:${mode}:${String(index)}`,
    tags: [],
    revalidate: 60,
    expire: 600,
    fill,
  };

  const instances = Array.from({ length: 4 }, (_, at) =>
    createKeptCache({ store: storeFor(mode, region(at)), wait: 250 }),
  );

  const times = await Promise.all(
    Array.from({ length: 20 }, async (_, at) => {
      const start = performance.now();

      await instances[at % 4]?.serve(call);

      return performance.now() - start;
    }),
  );

  return { fills, times };
}

try {
  await pool.query(postgresCacheSql(tables));

  for (const mode of [
    "no lease",
    "Runtime Cache lock",
    "postgresKeptLease",
  ] as const) {
    const fills: number[] = [];
    const times: number[] = [];

    for (let index = 0; index < rounds; index += 1) {
      const result = await round(mode, index);

      fills.push(result.fills);
      times.push(...result.times);
    }

    console.log(
      `${format(`miss, ${mode}`, summarize(times))}  fills per key ${String(Math.min(...fills))} to ${String(Math.max(...fills))}`,
    );
  }
} finally {
  await pool.query(
    `drop function if exists public.${tables.functionPrefix}_get(text, text[], bigint);
drop function if exists public.${tables.functionPrefix}_mark_tags(text[], text, bigint, bigint);
drop function if exists public.${tables.functionPrefix}_lease(text, text, bigint, bigint);
drop table if exists public.${tables.entriesTable}, public.${tables.tagsTable}, public.${tables.leasesTable}`,
  );
  await pool.end();
}

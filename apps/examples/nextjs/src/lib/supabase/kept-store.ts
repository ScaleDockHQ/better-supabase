import type { KeptStore } from "better-supabase/server";

import "server-only";
import { getCache } from "@vercel/functions";
import {
  postgresKeptLease,
  postgresKeptStore,
} from "better-supabase/cache-postgres";
import {
  memoryKeptStore,
  vercelRuntimeCacheAdapter,
} from "better-supabase/server";

import { env } from "@/env";
import { serviceSupabase } from "@/lib/service-supabase";

/**
 * Where `bsb.kept()` keeps its entries, by `BSB_KEPT_STORE`: `memory` per
 * instance, `postgres` in the cache tables, or `vercel` in the Runtime Cache
 * with a Postgres lease so one instance fills a missing key. The cache tables
 * are granted to the service role only; an entry holds a value the fill read as
 * its caller, so RLS stays the authority and no tenant row is read with the
 * key.
 */
export function keptStore(): KeptStore {
  switch (env.BSB_KEPT_STORE) {
    case "postgres": {
      return postgresKeptStore({ client: serviceSupabase() });
    }

    case "vercel": {
      return vercelRuntimeCacheAdapter(getCache, {
        lease: postgresKeptLease({ client: serviceSupabase() }),
      });
    }

    case "memory": {
      return memoryKeptStore();
    }

    default: {
      const unreachable: never = env.BSB_KEPT_STORE;

      return unreachable;
    }
  }
}

import { postgresCacheSql } from "better-supabase/cache-postgres";
import { Client } from "pg";

/**
 * With BSB_REMOTE_CACHE_STORE=postgres or BSB_KEPT_STORE=postgres or vercel
 * (its lease), creates the cache tables and functions on the local stack and
 * empties them, so both instances start cold.
 */
export default async function setup(): Promise<void> {
  const postgres =
    process.env["BSB_REMOTE_CACHE_STORE"] === "postgres" ||
    process.env["BSB_KEPT_STORE"] === "postgres" ||
    process.env["BSB_KEPT_STORE"] === "vercel";

  if (!postgres) {
    return;
  }

  const client = new Client({ connectionString: process.env.SUPABASE_DB_URL });
  await client.connect();

  try {
    await client.query(postgresCacheSql());
    await client.query(
      "truncate public.bsb_cache_entries, public.bsb_cache_tags, public.bsb_cache_leases; notify pgrst, 'reload schema'",
    );
  } finally {
    await client.end();
  }
}

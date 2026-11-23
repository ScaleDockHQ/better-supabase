// A `"use cache: remote"` handler over Supabase Postgres. next.config.ts uses
// it when BSB_REMOTE_CACHE_STORE is `postgres`. Run `postgresCacheSql()` from
// `better-supabase/cache-postgres` in a migration first (the e2e setup does it
// for the local stack); the tables and functions are granted to the service
// role only.
import { createClient } from "@supabase/supabase-js";
import { postgresCacheHandler } from "better-supabase/cache-postgres";
import process from "node:process";

const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
const key = process.env.SUPABASE_SECRET_KEY;

if (!url || !key) {
  throw new Error(
    "The Postgres cache handler needs NEXT_PUBLIC_SUPABASE_URL and SUPABASE_SECRET_KEY.",
  );
}

export default postgresCacheHandler({
  client: createClient(url, key, { auth: { persistSession: false } }),
  development: process.env.NODE_ENV === "development",
  onError: (error) => {
    console.warn(error.message);
  },
});

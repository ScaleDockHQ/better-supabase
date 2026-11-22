// A `"use cache: remote"` handler over Supabase Postgres. Point
// `remoteCacheHandler` in next.config.ts at this file to use it. Run
// `postgresCacheSql()` from `better-supabase/cache-postgres` in a migration
// first; the tables are readable by the service role only.
import { createClient } from "@supabase/supabase-js";
import { postgresCacheHandler } from "better-supabase/cache-postgres";
import process from "node:process";

const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
const key = process.env["SUPABASE_SERVICE_ROLE_KEY"];

if (!url || !key) {
  throw new Error(
    "The Postgres cache handler needs NEXT_PUBLIC_SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY.",
  );
}

export default postgresCacheHandler({
  client: createClient(url, key, { auth: { persistSession: false } }),
  development: process.env.NODE_ENV === "development",
  onError: (error) => {
    console.warn(error.message);
  },
});

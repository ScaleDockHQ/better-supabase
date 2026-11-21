import { addCacheTag, invalidateByTag } from "@vercel/functions";
import { cacheRoute, vercelCdnCache } from "better-supabase/server";

import { betterSupabase } from "./lib/supabase";

/**
 * Tags the responses `/api/customers` sends, so the CDN can drop them by table
 * or by row. Call `cdn.tag(...)` with the tags of what the handler read.
 */
const cdn = vercelCdnCache({ addCacheTag, invalidateByTag });

/** Attach it to mutations made through `db`, in the same process. */
betterSupabase.cache(cdn);

let handler: ((request: Request) => Promise<Response>) | undefined;

/**
 * Receives the change notifications `cacheInvalidationSql()` sets up in
 * Postgres (and Supabase Database Webhooks), so a write made by another
 * service, a cron job or the SQL editor expires the same tags. Built on the
 * first request, so the secret is read then. Mounted before the `/api/*`
 * middleware, because the caller sends a bearer secret, not a Supabase
 * session.
 */
export function cacheHook(request: Request): Promise<Response> {
  handler ??= cacheRoute({
    betterSupabase,
    caches: [cdn],
    bearer: process.env["BETTER_SUPABASE_CACHE_HOOK_BEARER"],
  });

  return handler(request);
}

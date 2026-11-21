---
"better-supabase": minor
---

Expire cached reads when a write comes from outside the process, and cache public reads without the service role.

- `cacheRoute` (`better-supabase/server`) verifies a bearer token or a Standard Webhooks signature and expires the `bsb:` tags of a change. It reads the trigger's payload, a Supabase Database Webhook and an outbox CloudEvent.
- `cacheInvalidationSql` (`better-supabase/sql`) generates `better_supabase.notify_cache()` and statement-level triggers that send the changed table, ids and tenants through `pg_net`. Write its output into a migration, then store the route URL and the token in Vault with `select vault.create_secret('https://app.example.com/hooks/cache', 'bsb_cache_url')` and `select vault.create_secret('<token>', 'bsb_cache_bearer')`. Enable the `pg_net` and `supabase_vault` extensions first. Without the URL secret the triggers do nothing.
- `vercelRuntimeCacheAdapter(getCache)` and `vercelCdnCache({ addCacheTag, invalidateByTag })` are cache adapters over `@vercel/functions` (`>=3.11.3 <4`, an optional peer you pass in). `encodeCacheTag` escapes the characters Vercel splits tags on.
- `bsb.public()` (`better-supabase/next`) returns an anonymous context for `'use cache'` reads, so Row Level Security applies and the service role stays out of shared caches.
- Doctor rule BS640 reports a plain `"use cache"` function that reads `cookies()`, `headers()`, `bsb.cached()`, `bsb.context()` or `bsb.user()`.

Upgrade: nothing changes until you add the route, the SQL and the secrets. `pg_net` sends once and doesn't retry, so keep a short `cacheLife` as the backstop. See the Vercel cache invalidation page in the docs.

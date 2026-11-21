# 1131: Expire cache tags for writes that leave the process

- Status: accepted
- Date: 2026-11-21

## Context

`betterSupabase.cache(adapter)` expires cached reads only for writes that go
through `db` in the same process. A write from another service, a cron job, an
Edge Function or the SQL editor left every cached read stale until its
lifetime ended. ADR 0850 listed the Vercel cache products as a roadmap item.

Facts checked against `@vercel/functions` 3.11.3 and the Vercel docs:

- A purge by tag covers the CDN cache, the Runtime Cache and the Next.js Data
  Cache together.
- `invalidateByTag` and `addCacheTag` do nothing outside a Vercel request
  context. `expireTag` builds its URL query without escaping.
- Tags are limited to 256 bytes, 128 per response and 16 per purge call, and a
  comma separates tags in a header.
- `pg_net` queues a request and sends it after the transaction commits. It
  doesn't retry.
- `base.contextFor({ kind: "none" })` builds an anonymous context that reads no
  cookie or header, so it runs inside a plain `'use cache'` scope (tested in
  `tests/next/public.test.ts`).

## Decision

1. `cacheRoute` (`better-supabase/server`) verifies a bearer token or a
   Standard Webhooks signature and expires the tags of a change. It reads the
   trigger's payload, a Supabase Database Webhook and an outbox CloudEvent,
   makes one `CacheTarget` per tenant, expands a delete with
   `invalidationTargets`, and answers 502 when an adapter throws so the sender
   retries. A table the schema doesn't know answers 200.
2. `cacheInvalidationSql` (`better-supabase/sql`) generates
   `better_supabase.notify_cache()` and one statement-level trigger per table
   and event, using transition tables so a statement sends one request. The URL
   and the bearer token live in Vault (`bsb_cache_url`, `bsb_cache_bearer`),
   never in a migration. Without the URL the function does nothing. A statement
   over `maxRows` sends no ids and the route expires the whole table. A script
   writes the SQL into a migration; no module is added to `src/sql/modules`.
3. `vercelRuntimeCacheAdapter(getCache)` and `vercelCdnCache({ addCacheTag,
   invalidateByTag })` are `CacheAdapter`s over structurally typed functions
   that the app passes in. `@vercel/functions` stays an optional peer with the
   existing tested range. Both send tags through `encodeCacheTag`, which escapes
   what Vercel splits or parses on and drops a tag over 256 bytes, and purge in
   batches of 16.
4. `bsb.public()` returns a context for `'use cache'` reads that anyone may
   see. It uses the anonymous context, so Row Level Security applies and the
   service role is never used, and it tags and sets the life as `bsb.cached()`
   does. Doctor rule BS640 reports a plain `"use cache"` function that reads
   `cookies()`, `headers()`, `bsb.cached()`, `bsb.context()` or `bsb.user()`.

## Alternatives considered

- Supabase Realtime in the server: needs a long-lived process, which a function
  doesn't have.
- `pg_notify` with a listener: same problem, and a missed notification is lost.
- One tag per row and tenant without encoding: a composite key or a tenant with
  a comma splits into several tags.
- Keeping `bsb.admin()` for public reads: it works, but it skips Row Level
  Security, so a wrong filter leaks data into a shared cache.
- A module under `src/sql/modules`: the cache trigger depends on the tables the
  app watches, so it is generated from the schema instead.

## Consequences

A write from any source expires the same tags as one made through `db`. The
route is the only new endpoint, and it refuses unsigned requests. The
notification is at-most-once, so a short `cacheLife` stays the backstop. A
Vercel-only app needs one adapter, because a tag purge covers all three layers.
Revisit this when Vercel adds a way to purge by prefix, which would replace the
per-row tags for bulk writes.

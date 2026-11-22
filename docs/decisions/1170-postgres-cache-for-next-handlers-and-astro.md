# 1170: A Postgres cache for Next.js `cacheHandlers` and the Astro route cache

- Status: accepted
- Date: 2026-11-22

## Context

ADR 1151 and ADR 1155 listed the Postgres Next.js `cacheHandlers` and the Astro
route cache provider as not built. The core route cache (`cacheRoute` in
`src/core/cache-route.ts`) already takes a `Request` and answers a `Response`,
so every framework with route handlers (Astro endpoints, Nitro, Hono, Express)
can call it with a `CacheAdapter`. What was missing was a shared store: Next.js
`cacheHandlers` and Astro's `CacheProvider` both need somewhere every instance
reads and writes entries and tag states.

Astro 7.4.11 does expose the provider interface (`CacheProvider` with
`onRequest` and `invalidate`), and the built-in memory provider shows the
contract: Astro sets `CDN-Cache-Control` and `Cache-Tag` on the response and the
provider stores and serves it. That was checked against the installed package.

## Decision

One subpath, `better-supabase/cache-postgres`, plus `better-supabase/cache-postgres/astro`
because Astro loads a provider from a module whose default export is the factory.

- `postgresCacheStore` keeps entries and tag states in two tables through
  PostgREST with a service role client. Its methods return a `Result` with plain
  `DbError`s and never throw. Values are base64 text, so the entry uses no
  Node built-in and is a runtime entry (invariant 6).
- `postgresCacheHandler` is the Next.js `CacheHandler`, typed structurally
  (no import from `next`, no new optional peer). A store error is a miss or a
  skipped write and goes to `onError`. A failed `updateTags` throws, because a
  lost invalidation serves stale data.
- `astroPostgresCache` and the default export are the Astro provider. They never
  store a response with `Set-Cookie` or `Vary: Cookie`.
- `postgresCacheSql()` returns the DDL for the app's own migration. Both tables
  enable row level security with no policy and revoke `anon` and
  `authenticated`. No table is added to `supabase/schemas`, so no migration of
  this repository changes.
- Tags are read in chunks of 128 through `chunkTags` in `src/core/tag-chunks.ts`,
  which holds the same 128 as `MAX_TAGS_PER_CALL` in `src/next/cache-tags.ts`.
  `applyCacheTags` keeps its own constant: importing the helper there grew the
  server chunks of 18 routes of the Next.js example by 13 to 22 bytes.
- A write from outside the process reaches both caches through `cacheRoute`,
  which needs no change.

## Alternatives considered

- A SQL module in `src/sql/modules`. Rejected: the tables hold cache data, not
  app data, and a module would add a migration to every installation.
- Separate subpaths for Next.js and Astro with separate stores. Rejected: one
  store means one tag semantics.
- Keeping `Vary: Cookie` responses. Rejected: it would serve one user's page to
  another.

## Consequences

- The tables are a hot path: each Next.js read costs one entry query and one tag
  query. Teams that need lower latency keep Vercel's handler for
  `cacheHandlers.default` and use this one for `remote`.
- Frameworks without a provider interface (Nuxt, Nitro) keep calling
  `cacheRoute` with their own adapters. No Nuxt or Nitro provider is built.
- Not verified here: a live `next build` against a running Supabase stack. The
  handler is covered by tests over an in-memory store and a stubbed client, and
  the example file type checks.

# 1240: Keep the sample's kept entries in a store that outlives the instance

- Status: accepted
- Date: 2026-11-25

## Context

`bsb.kept()` keeps its entries in `memoryKeptStore()` unless `createNext` gets
`kept: { store }`. The example app set none, so every instance and every
restart started cold: the hard-load measurements in
`docs/agents/one-round-trip-after.md` showed the same calls on a second hard
load, a second user and a load after a restart, because no entry survived.
Every shared kept read the plan adds (tenant counts, definitions, the shell)
needs a store that more than one instance can read.

## Decision

The sample reads a new env key, `BSB_KEPT_STORE`, in `src/lib/supabase/kept-store.ts`
and passes the store to `createNext`:

- `memory` (the default): `memoryKeptStore()`, one per instance.
- `postgres`: `postgresKeptStore` over the tables of `postgresCacheSql()`.
- `vercel`: `vercelRuntimeCacheAdapter(getCache)` with `postgresKeptLease`, so
  one instance fills a missing key while the entries stay in the Runtime Cache.
  `@vercel/functions` stays an optional peer typed structurally.

Both Postgres variants use the service role, which holds the cache tables
only. An entry holds what the fill read as its caller, so RLS stays the
authority and no tenant row is read with the service key. The key goes in
`env.ts`, `turbo.json` and `.env.example`; a maintainer sets `vercel` in all
three Vercel environments. The e2e setup creates the cache tables when the
key is `postgres` or `vercel`.

## Alternatives considered

- Default to `postgres` locally: the cache tables have no migration (the e2e
  setup creates them), so a plain `pnpm dev` would fail on a fresh stack.
- Default to `vercel` when `VERCEL=1`: the sample would change behavior
  without an explicit setting, and the key is the documented env row.
- A migration for the cache tables: they are the Next.js handler's tables
  and the library ships them as SQL to run, not as a module.

## Consequences

A kept entry survives a restart and is shared by instances when the key is
`postgres` or `vercel`. `experimental.durableUseCacheEntries` stays off.

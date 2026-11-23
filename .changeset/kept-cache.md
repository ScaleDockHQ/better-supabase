---
"better-supabase": minor
---

Add `bsb.kept(fn, options)`, which keeps a read in a store across requests and deploys. The function runs as the caller, under RLS, with one entry per user, tenant and authorization version, and a write to one of `tables` expires it. A stale entry is served while one call refreshes it. Pick the store with `createNext({ kept: { store } })`: `memoryKeptStore()` (the default), `vercelRuntimeCacheAdapter(getCache)`, which gains `expireTags`, or the new `postgresKeptStore()` from `better-supabase/cache-postgres`. An entry over 2 MB, 128 tags or 256 bytes per tag is not stored and is reported to `kept.onSkip`. See ADR 1221.

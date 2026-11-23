---
"better-supabase": minor
---

`bsb.kept()` and `postgresCacheHandler` fill a missing entry once. Concurrent misses in one process
share one fill. Across instances, `postgresCacheSql()` adds a `bsb_cache_leases` table and a
`bsb_cache_lease` function that hands one caller the fill; the others wait up to `wait` ms (250 by
default) for its entry, then fill themselves. Run `postgresCacheSql()` again in a migration to add
them. A `KeptStore` may implement `lease` and `release`; `vercelRuntimeCacheAdapter` does so with a
best-effort lock entry.

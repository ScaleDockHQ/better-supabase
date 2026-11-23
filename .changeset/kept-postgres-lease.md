---
"better-supabase": minor
---

`postgresKeptLease()` from `better-supabase/cache-postgres` returns the fill lease of `postgresKeptStore` on its own, and `vercelRuntimeCacheAdapter(getCache, { lease })` takes it. The entries stay in the Runtime Cache, and one instance fills a missing `bsb.kept()` key instead of each instance whose read raced the lock entry. The `KeptLease` type is exported from `better-supabase/server` and `better-supabase/cache-postgres`.

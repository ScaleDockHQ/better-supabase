---
"better-supabase": minor
---

Idempotency keys have a holder token, and the module adds leases. `begin_idempotent` returns a `holder` with the `started` state, and `complete_idempotent(scope, key, holder, ...)` and `release_idempotent(scope, key, holder)` act only for that holder, returning false after another caller took the expired key over; `createIdempotency().begin()` returns `holder`, and `complete` and `release` take it and return a boolean. The new `acquire_lease(key, seconds, scope)`, `extend_lease` and `release_lease` keep one holder per key until it releases or the lease expires, and `withLease(sql, key, fn)` from `better-supabase/blocks/jobs` runs a function while holding one. Breaking: `complete` and `release` need the holder, in SQL and TypeScript.

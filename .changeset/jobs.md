---
"better-supabase": minor
---

Jobs run as the user who enqueued them and report queue health, and `better-supabase/blocks/jobs` adds leases and rate limits. Run `better-supabase sql upgrade`.

- `bs.forContext(job.context)` returns repositories as the context's user and tenant, so RLS applies in the handler. It keeps a read-only support session read-only, and `claimsFor(userId, context)` rebuilds hook claims.
- `jobs.stats()`, `listDead()` and `retryDead()` serve admin pages, and `enqueue` takes `dedupe: "waiting"`.
- Under `scheduler: "drain"`, schedules record a tenant (`listSchedules`, `unscheduleAll`), `ensureSchedules` keeps a named set in step, `drainRoute` takes `monitor` hooks, and `devDrain` drains locally.
- `withLease(sql, key, fn)` holds one holder per key. `hit_rate_limit(scope, key)` and `createRateLimit().check()` limit any key, and `rateLimited(decision)` answers 429 with `Retry-After`.
- **Breaking:** `begin_idempotent` returns a `holder`, and `complete_idempotent` and `release_idempotent` (`createIdempotency().complete` and `release`) take it and return false after another caller took an expired key over.

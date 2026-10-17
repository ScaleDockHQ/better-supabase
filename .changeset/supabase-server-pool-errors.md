---
"better-supabase": minor
---

Repository calls on `ctx.postgres` and `ctx.postgresAdmin` now return `@supabase/server`'s pool errors (`POSTGRES_POOL_BUSY` and `POSTGRES_CONNECT_PAUSED`) as a `network` error with status 503 instead of `unexpected` with 500. `network` errors carry `retryAfter` in seconds when the pool reports how long it is paused, and the problem response sends it as `Retry-After`. A pool failure at the start of a `$many` transaction now returns an error for each operation instead of rejecting.

---
"better-supabase": minor
---

`server.warm()` and `bsb.warm()` load the JWKS and open the PostgREST, read replica, pool and flags connections before the first request, in parallel, and report a time per step. They never throw. `warm(bsb, { postgres, flags })` from `better-supabase/next/instrumentation` runs it from `register()` and logs a failed step. The auth docs say when `prefetchJwks: false` is still needed. See ADR 1221.

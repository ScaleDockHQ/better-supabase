---
"better-supabase": minor
---

With `debug.enabled`, `bsb.action` logs the request's database stats in the same format as the
`x-bsb-db-calls` header, because a server action cannot set response headers. `testAuthorizer`
checks that an authorizer ignores a `runtime.seed` for another user or a version that is not live.

---
"better-supabase": minor
---

`createPostgres({ pool })` runs on an existing `pg.Pool` or any object with `connect()` and `end()`, typed as the new `PgPool` and `PgPoolClient` exports of `better-supabase/postgres`. `list.parse()` now reads a typed `ListQueryInput` such as `{ page: 2, size: 10 }` instead of treating it as URL search params and falling back to page 1, and a non-string `q` such as `{ q: 5 }` reports `Must be text` instead of being accepted. `contextFromSupabase` throws a `TypeError` for an auth mode it does not know instead of returning it as the request context. The standards page lists the conformance test behind each adopted standard.

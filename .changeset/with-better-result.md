---
"better-supabase": patch
---

New subpath `better-supabase/better-result`: `withBetterResult(db, toResult)` returns a view of `db` whose repository methods, `$rpc`, `$run`, `$many`, `$search` and list queries (`$list`) return better-result `Result` values, so call sites no longer convert each result. `toResult` is a `defineBetterResultErrors` converter or `{ Result, mapError }`. better-result is an optional peer (`>=3 <4`) that the subpath imports only for types.

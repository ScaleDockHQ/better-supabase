---
"better-supabase": minor
---

`powersyncExecutor` takes a `fallback` executor. Reads that SQLite can't run (an include, full-text search, a function source) and `db.$rpc` go to the fallback, usually `postgrestExecutor(supabase)`; writes never fall back. `checkSqlite(betterSupabase, list, { all: true })` returns every unsupported feature a list uses instead of the first. `db.$rpc` on an executor without `rpc` now returns a `DbError` of kind `unsupported` (HTTP 501) instead of `invalid_request`. The PowerSync docs add a guide to porting a PostgREST list.

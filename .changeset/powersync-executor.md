---
"better-supabase": minor
---

Run the same repositories and list definitions on PowerSync's local SQLite database with the new `better-supabase/powersync` entry. `powersyncExecutor(db)` returns the same `Result` and `DbError` values as the PostgREST and Postgres executors: rows come back in the PostgREST shape (booleans, parsed JSON, ISO timestamps), SQLite constraint errors map to `conflict`, `foreign_key`, `not_null` and `check`, and inserts get a client-side id when they leave the key out. Timestamps compare by instant whatever offset the text carries, `like` stays case-sensitive and `ilike` case-insensitive. `watch()` reruns a query when PowerSync reports a change to its tables, and `checkSqlite()` compiles a list definition for SQLite in a test. What SQLite can't run (includes, full-text search, function sources) fails before it runs with the new `DbError` kind `unsupported` (HTTP 501).

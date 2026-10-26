---
"better-supabase": minor
---

`better-supabase db diff` plans with pg-delta's library on a local pg-delta project. A rename becomes a rename only when a migration records `-- bsb: rename old -> new`, and a diff that drops tables or columns stops with a `check_failed` error until you pass `--allow-data-loss`. The shadow database comes from `provisionCoLocatedShadow`, so `pg_dump`, `psql` and `BSB_PG_BIN` are no longer used. Install `@supabase/pg-delta` and `@supabase/pg-topo` (optional peers) to use it. The Supabase CLI still runs for the migra workflow and remote databases.

---
"better-supabase": patch
---

The CLI reads `$SUPABASE_DB_URL` when `$DATABASE_URL` is unset, so `gen`, `introspect`, `doctor` and `seed --apply` connect with the variable the Supabase CLI and `better-supabase env` write. `$DATABASE_URL` still wins when both are set. The `gen` docs now list the real source order: a configured `source.snapshot` comes before `source.dbUrl`.

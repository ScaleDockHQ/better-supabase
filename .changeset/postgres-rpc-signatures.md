---
"better-supabase": patch
---

The direct Postgres executor looks a function up in `pg_proc` once per executor instead of on every call without generated metadata (block calls included), and looks it up again after an error that says the function changed. Arguments for `OUT` and `TABLE` parameters are dropped from the call, as PostgREST drops them.

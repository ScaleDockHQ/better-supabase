---
"better-supabase": minor
---

Every SQL module's data file repeats the `create extension if not exists` statements of its schema file (`pg_jsonschema` and `vector` in `extensions`, `pgcrypto`, `citext`, `pgmq`), so `better-supabase sql data` lands them in a migration when pg-delta leaves an extension in a schema it doesn't manage out of the plan. This replaces the per-module `extensions` field from the pgmq change.

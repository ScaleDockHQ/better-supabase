---
"@better-supabase/cli": minor
---

Support the Supabase CLI's pg-delta engine and native local stack. When `supabase/config.toml` sets `[experimental.pgdelta] enabled = true`, `better-supabase sql add` and doctor (BS304, BS305, BS404 and `--fix-grants`) name `supabase db schema declarative sync` instead of `supabase db diff`, BS404 asks for the grants in the schema file that defines the hook, and the declarative schema files are read from `declarative_schema_path` in name order, since pg-delta ignores `schema_paths`. `better-supabase env` falls back to `supabase status --env` when `[experimental] stack = true` makes `supabase status -o json` fail.

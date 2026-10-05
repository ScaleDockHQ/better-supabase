---
"better-supabase": patch
---

SQL kit functions pass `supabase db lint` when the app defines none of the optional SQL hooks. `purge_audit_log`, the notifications audience hook and every `before_*` and `after_*` hook now call the app's function through dynamic SQL, so plpgsql_check no longer reports a missing `audit_retention` or `after_profile_sync`. `audit_event` rejects `restricted` details with `22023` when the audit module has no restricted table, instead of dropping them. When `sql.dir` is a folder inside the declarative schema folder, the `better-supabase-data` files go next to the schema folder (`declarative_schema_path` under pg-delta), so `supabase db schema declarative sync` no longer loads their rows. Run `better-supabase sql sync` and create a migration to pick up the new function bodies.

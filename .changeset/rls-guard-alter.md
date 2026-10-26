---
"better-supabase": patch
---

`rls-guard` also fires after `alter table`, so a statement that disables row level security on a table outside the Supabase-managed schemas is undone straight away. Run `better-supabase upgrade` to refresh the module's data file (ADR 0104).

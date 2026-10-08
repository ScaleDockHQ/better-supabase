---
"better-supabase": minor
---

Data exports leave the library's own secrets out: `api_keys` is never exported and invitations are exported without their token hash, while the purge still deletes both. `sql.modules.data-lifecycle.options.tables` takes `export: false` to keep a table out of exports while the purge still deletes it, and an entry for a table a module already contributes replaces the module's entry. `data_lifecycle_tables()` returns an `exported` column, and `sql upgrade` moves the module to version 4.

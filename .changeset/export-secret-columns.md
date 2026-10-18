---
"better-supabase": minor
---

`blocks.data-lifecycle.options.omitPattern` leaves columns out of data exports by name. `true` matches `token`, `secret`, `_hash`, `password`, `api_key` and `license_key`, and a string is a Postgres regular expression; `data_lifecycle_tables()` then appends the matching columns of each listed and `autoTables` table to its `omit` when an export runs. It is off by default, so existing exports don't change. Doctor's new BS341 warns about exported columns that match the built-in pattern and that no `omit` or `omitPattern` leaves out.

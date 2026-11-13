---
"better-supabase": patch
---

`db.$rpc` returns table rows in app casing in a schema with `lazyTables`, also when the function's result table has not loaded yet. The call now loads that table before it builds the select and decodes the rows. Before, the row came back with database keys such as `created_at`, and the function kept that result for the rest of the process, so a later call stayed undecoded even after the table loaded.

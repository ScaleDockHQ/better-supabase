---
"better-supabase": patch
---

`chain_link()` no longer throws when a row trigger runs without the statement-audit temp table. The owner check reads the table oid from `to_regclass`, which returns null when the table is absent, instead of casting a name that Postgres resolves while planning the statement.

The published config schema no longer lists `blocks.tasks.options.identifiers`. The tasks options have no such property, and the default of `tenant` was not one the config reads.

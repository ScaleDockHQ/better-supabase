---
"better-supabase": minor
---

`gen` reads `@bsb` table comment tags (ADR 0102): `subject`, `realtime` and `vector-search` on a table behave like `subjects`, `database.realtime` and `vectorSearch` entries, and a key the config sets itself wins. `better-supabase migrate schema-first` writes the tables that `tables` (the old `appTables`) renders as files you own under `supabase/schemas`, with the config's per-table features as tags. The config keys keep working in this release step; delete `tables` after running the command.

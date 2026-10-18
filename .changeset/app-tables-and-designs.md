---
"better-supabase": minor
---

`appTables` declares the tables your app owns. `better-supabase sql sync` writes them to `supabase/schemas/900_better_supabase_app_tables.sql` with an `id`, the tenant or user column, timestamps and the row level security that `sql.scope` gives the blocks; columns can reference another app table, `auth.users` or a block's table. `better-supabase/preset` adds `encodeDesign`, `decodeDesign`, `isDesignCode`, `designOf`, `designConfig`, `designConfigSource`, `designInstallCommand` and `designApplyCommand` for the `&design=` code the Create canvas writes, and `init --preset` and `apply --preset` take a `/create` URL with a design and write its app tables and extra columns into the config.

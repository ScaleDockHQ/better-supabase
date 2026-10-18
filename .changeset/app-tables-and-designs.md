---
"better-supabase": minor
---

`appTables` declares the tables your app owns. `better-supabase sql sync` writes them into `900_better_supabase_app_tables.sql` with the scope column (per tenant, per user or open to signed-in readers), row level security, grants, indexes and the `updated-at` trigger, plus a pgTAP test that checks each table's policies and that a stranger can't read or insert outside their scope. Columns take a closed list of types, defaults from an allowlist and references to another app table, `auth.users` or a block's table, which follows the block's renames.

`better-supabase/preset` encodes a Create design (app tables, extra columns on block tables and canvas positions) into a code that rides on the `/create` URL as `&design=`: `encodeDesign`, `decodeDesign`, `designOf`, `designConfig`, `designConfigSource`, `designInstallCommand` and `designApplyCommand`. The preset catalog lists the table each block's `extraColumns` extends. `init --preset <url>` writes the design's `appTables` and `extraColumns` into the new config, and `apply --preset <url>` merges them into the config you have.

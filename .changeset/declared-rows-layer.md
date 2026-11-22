---
"better-supabase": minor
---

Add the declared rows layer. `better_supabase.declared_defaults` holds option set items, pipeline stages, approval floors and numbering formats the app owns, and the block functions read it before the config literal, so a config without declared rows behaves as before. An option set binding can omit `items`; a field with neither declared nor literal items raises `OPTION_SET_DEFAULTS_MISSING`. The new `better-supabase db rows` command turns each file in `supabase/rows` (upserts of literal rows by their natural key) into a data migration stamped with the hash of its statements, writes a new migration only when the hash changes, and with `--check` exits 1 when a file has none. A removed row stays in the database and is reported, unless the file carries `-- bsb-rows: delete-removed`. `approval_policy` is now `stable` instead of `immutable`.

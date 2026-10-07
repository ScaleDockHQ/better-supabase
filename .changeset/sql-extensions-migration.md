---
"better-supabase": minor
---

`sql add`, `sql sync` and `sql upgrade` write the extensions the module schemas create, and that no migration creates yet, into a `<stamp>_better_supabase_extensions.sql` migration stamped before the schema migration you generate next. Objects in the schema migration that need an extension while it applies (a `jsonb_matches_schema` check constraint from `jsonb-schemas`, a pgmq queue) then find it on a fresh database, so no app writes an extension migration by hand. A migration you wrote that creates the extension counts. `sql data` now fails while a module extension is missing from every migration other than the data migrations, and names `sql sync` as the fix. Doctor BS321 names `sql sync` too.

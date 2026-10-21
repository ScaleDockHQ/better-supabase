---
"better-supabase": minor
---

Add `better-supabase db diff`, which turns the declarative schema into a migration with the Supabase CLI's command for the workflow and, when the shadow database can't start because no System V shared memory segment is left, diffs inside the running stack instead. `--in-stack` skips the shadow database, `-f <name>` writes the migration, and `$BSB_PG_BIN` names the directory with `pg_dump` and `psql` when the CLI can't find them next to the postmaster.

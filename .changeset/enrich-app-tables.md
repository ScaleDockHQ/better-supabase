---
"better-supabase": minor
---

A `tables.<name>` entry can now name a table your own schema already creates. Instead of refusing it, better-supabase enriches the table: it skips `create table` and adds only the columns the table lacks (the scope column, the timestamps, the id when it has none, and the columns you list) with `alter table ... add column if not exists`, nullable unless they have a default. Enriching never overwrites what your schema wrote: the scope's policies are named `bsb_<table>_<command>` on your table, so a policy of yours named `<table>_select` stays, and your grants stay too, since the entry only adds the grants its scope needs. The scope column gets a `not valid` not-null check, so new rows must fill it while `better-supabase db backfill` fills the old ones. Row level security, the scope's grants and policies, the restrictive `bsb_tenant_scope` policy, subject permissions, events, the `updated_at` trigger, versions, read audits, rollups and lookups render the same as for a table it creates. Each feature works on its own, so `scope: "none"` with only `subject` or only `events` adds no scope column.

Doctor adds two checks. BS237 reports permissive policies of your own on a scoped app table (a hint when `bsb_tenant_scope` narrows them, a warning in `user` scope) and the grants on an enriched table beyond its scope (a warning when they reach columns the entry restricts). BS238 counts the rows of an enriched table without an owner and names the `db backfill` command. BS228 no longer reports a required column without a default that an enriched table keeps nullable.

`gen` filters a table on the tenant column its subject names (`subjects.<type>.tenant`), so a block over your table with its own tenant column gets the memberships filter too.

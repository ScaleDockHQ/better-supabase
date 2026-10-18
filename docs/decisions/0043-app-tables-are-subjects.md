# 0043: An app table becomes a subject through `appTables.<name>.subject`

- Status: accepted
- Date: 2026-10-18

## Context

No-code database builders (Airtable, Baserow, NocoDB, Notion) give every
record comments, files, history and search without setup. In
better-supabase those features are blocks that attach to subjects
(`config.subjects`, ADR 0020), but an app table (ADR 0040) had to be
registered in `subjects` by hand, with its tenant column, title and rank
column repeated, and nothing added the columns a subject reads. Create had
no way to say "this table has comments".

## Decision

An app table takes `subject: { type, title?, url?, search?, permissions?,
rank?, softDelete? }`. `resolveConfig` merges it into `subjects`
(`withAppTableSubjects`), so the subject registry, every block that reads
it and `doctor` see one list. The merge fills in the table name, the id
type and the tenant column from the table's scope, and refuses a type that
`subjects` already declares.

`rank: true` adds a `rank` column (`text collate "C" not null default 'V'`)
and an index, and `softDelete` adds `deleted_at`. A user column with either
name fails `sql sync`.

Blocks render before the app tables file (`900_better_supabase_app_tables.sql`
sorts last), so a block can't create a trigger on an app table. The search
block skips app tables in its own file and the app tables file writes their
search triggers. `search_reindex` checks that an app table exists before it
reads it, because block data can run before the app tables file.

## Alternatives considered

Asking apps to list app tables in `subjects` works today, but repeats the
table's scope and needs the columns added by hand. Moving the app tables
file before the blocks would let blocks add triggers, but app tables
reference block tables (organizations, tags), so they must come after.

## Consequences

A design that uses `subject` writes design format 2; older releases reject
it with a message to update. Blocks that create triggers per subject must
follow the search block's pattern for app tables. Create can now turn
record features on per table.

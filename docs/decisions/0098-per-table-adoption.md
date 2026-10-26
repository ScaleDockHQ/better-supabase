# 0098: Detect the app's tables per table instead of an adopt mode

- Status: accepted
- Date: 2026-10-24

## Context

A block ran in one of three modes: `managed` created every table, `adopt`
created none and ran over tables the app already had, and `custom` wrote no
SQL. The choice was per block. An app that had one of a block's tables and
not the others had to adopt all of them and create the rest itself, or rename
its table out of the way. An app with its own declarative schema files had to
know which blocks supported adopt mode and set `ownership: "adopt"` before
the first `upgrade`, or the block's `create table if not exists` silently
kept the app's table and wrote functions against columns it might lack.

Since then the CLI detects the app's tables: a table its own schema files
create, or a table in the saved snapshot that no block file or module
migration created, lands in `layout.ownTables`. Each module declares a
spec per table (`names.tables.<t>`: columns, optional, typed, and `app` when
the app's table can stand in). With that, the mode carries no information
the CLI can't find out itself.

## Decision

Adoption is per table and detected. `BlockMode` is `"managed" | "custom"`.
In managed mode, `ctx.owns(table)` is false for a table `ownTables` lists
whose spec has `app`: the module skips its `create table`, adds the columns
it needs that the table lacks with `add column if not exists`, and writes its
functions, policies, triggers and indexes over it (`src/sql/app-owned.ts`,
`src/sql/over-app-tables.ts`). A table whose spec has no `app` is always the
block's, and a table of that name in the app's schema is an error.

`ownership: "adopt"` is rejected by the config schema with a message that
names `better-supabase codemod`; the 0.15 codemod removes the key and keeps
`tables` and `columns` (`src/cli/sql/config-adopt.ts`). `add --adopt`
proposes `tables` and `columns` mappings only. Doctor BS330, BS342 and BS344
and `adoptedTables` read `ownTables` built from the catalog instead of the
mode. Migration-only options are accepted for a block over a table the app
already has. This supersedes the adopt part of block ownership; `custom`
stays as it was, and ADR 0018's subject link tables are checked for every
block that names them in `blocks.<name>.on`.

## Alternatives considered

- Keep `adopt` next to detection, as an override. It would mean two ways to
  say the same thing, and a block in adopt mode would still refuse to create
  the tables the app lacks.
- Make adoption per table but explicit, with an `ownership` per table in the
  config. The CLI already knows which tables the app's schema creates, so the
  key would only repeat what it detects and drift from it.

## Consequences

An app can install a block over some of its tables and let the block create
the rest, and adding a table to its own schema later moves that table over
without a config change. The change is breaking: configs with
`ownership: "adopt"` fail validation until the codemod runs. Detection reads
the app's files or the snapshot, so a table created outside both (by hand in
the dashboard, for an app on declarative schemas) isn't seen; doctor's checks
over the catalog report what that misses. If apps need a block to create its
own table next to one of the app's with the same name, revisit with an
explicit per-table override.

## Amendment: every block table is adoptable (2026-10-25)

A table spec without `app` made the block refuse an app that already had the
table, so an app with its own schema still had to rename tables out of a
block's way. Every `names.tables` spec now has `app`, and the rule is a test:
`tests/sql/over-app-tables.test.ts` fails for a spec without it, with no
allowlist, and `tests/sql/modules/over-app-modules.test.ts` renders every
module over app tables at their default names. Over an app table a module
guards its optional columns with `ctx.has`, writes typed columns through
`ctx.cast`, gives each `on conflict` target its own `bsb_` unique index, and
builds JSON column by column rather than from the whole row.

Two kinds of table stay narrower:

- The `workflow-sdk` world tables have no spec. The Workflow SDK defines their
  shape and reads them directly, so an app table at one of their names stays
  an error.
- A spec with `app.onlyWhenMapped` (the catalog's channel, translation and
  media tables) runs over the app's table only when `blocks.<name>.tables`
  maps it. Unmapped, the block creates its own, and an app table at the
  default name is an error.

Usage history over the app's table is never partitioned; the app's table
needs an increasing `bigint` id. The own-schemas docs page lists every
adoptable table with its required and typed columns; `pnpm catalog` writes
the list from the specs, and `catalog:check` and `docs:drift` fail when it is
stale.

## Dashboard-created tables

A table made in the Supabase dashboard exists only in the database. Detection reads schema
files, migrations and the saved snapshot, so such a table is not adopted until it reaches one of
them. The supported path is `supabase db pull` or `better-supabase gen --save-snapshot`, after
which `init` and `doctor --adoption` list the table (ADR 0101). The CLI does not read the live
database during `add` or `upgrade`, so generated SQL stays reproducible from files.

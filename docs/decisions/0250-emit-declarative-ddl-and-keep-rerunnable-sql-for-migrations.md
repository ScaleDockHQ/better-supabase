# 0250: Emit declarative DDL and keep rerunnable SQL for the migrations workflow

- Status: accepted
- Date: 2026-11-06
- Amends: 0249

## Context

Modules wrote `create table if not exists`, `drop policy if exists` before each
policy, `add column if not exists` and `drop function if exists`, so a file
could run over a database that already held its objects. A schema diff reads
the files as the end state, and each guard hides what a file declares: a
table that may or may not exist, a policy removed and recreated on every run.
The migrations workflow still repeats every module in each migration, so it
needs the guards.

## Decision

`src/sql/pipeline/static.ts` turns a module file into declarative DDL
(`staticDdl`) after the app-table pass. It removes `drop policy`, `drop
trigger`, `drop function`, `drop index` and `drop constraint` when they carry
`if exists`, removes `if not exists` from `create table` and `create index`,
and removes it from `add column` on tables the block owns. A column the same
file's `create table` declares is not added again. A table the app owns keeps
`if not exists` on its columns and indexes, because an app file may declare
them. The app tables file keeps `if not exists` everywhere, since its tables may
exist in files the block can't see, and loses only the drops.

A check that a later `add constraint` replaces by name (a column's
`<table>_<column>_check`, the table's `<table>_check` or a named inline
constraint) goes into the `create table` with its final expression, and the
`add constraint` goes, because a schema diff holds one constraint per name. A
replacement that reads a column a later statement adds leaves the `create
table` and stays as the `add constraint` after that column.

`rerunnableDdl` does the reverse for a layout with `rerunnable: true`: a `drop
policy if exists` before each `create policy`, a `drop trigger if exists` before
each `create trigger`, a `drop constraint if exists` before each `add
constraint`, and `if not exists` on each added column. `moduleLayoutFor` sets
`rerunnable` under the migrations workflow, upgrade steps are always
rerunnable, and `migrationBetween` renders both designs that way.

`src/sql/emit/` holds the statement builders (`createPolicy`, `createTrigger`,
`createFunction`, `createIndex`, `createTable`, `addColumn`, `addConstraint`,
`grantExecute`, `grantTable`, `commentOn`). `renderPolicy` no longer takes
`drop`. `addForeignKey`, `addCheck` and `ensureCheck` write one `alter table ...
add constraint` instead of a `do` block, `ownRowPolicies`, `lockTable`,
`updatedAt` and `recordTrigger` use the builders, and the tenant scope no longer
opens each file with a `do` block that drops its policies.

The result loads into Postgres through pg-delta: `supabase db schema
declarative sync --strict-coverage` reads the repository's module files into a
shadow database and reports no schema changes after the migration that removes
the `api` wrappers of the prelude helpers and the constraint hash comments,
and `pnpm supabase:test` passes all 172 pgTAP files.

## Alternatives considered

Rewriting every module template to write static DDL by hand would touch about
660 files for the same output. A pass over the statements keeps the templates
and moves the rule to one place that tests cover. Dropping the migrations
workflow's guards would break upgrades that run over an installed database.

## Consequences

`do` blocks that create objects, `execute format` loops and top-level inserts
in module files remain; doctor counts them and the count may only fall. The
drops that removed old function signatures are gone from the declarative files;
a schema diff removes an overload the files no longer declare. The render cache
key does not yet include the generator's own code, so a dev checkout that
changes the generator must clear `node_modules/.cache/better-supabase`.

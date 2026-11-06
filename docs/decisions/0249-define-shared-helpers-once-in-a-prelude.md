# 0249: Define shared helpers once in a prelude file

- Status: accepted
- Date: 2026-11-06
- Amends: 0248

## Context

Every module file pasted the helpers it called: `actor_may_write` and
`raise_actor_readonly` sat in 143 of 183 files, `import_run` in 43, the memo
functions and `replace_equivalent_triggers` in three, and each file created
`better_supabase.blocks` with `create table if not exists`. A schema diff reads
all files at once, so a function defined in 143 files has 143 owners, and a
file edit can't tell which copy a change belongs to.

## Decision

`renderBlocks` writes one more schema file, `900_better_supabase_000_prelude.sql`
(module `prelude`, `-- @bsb-block prelude@1 managed`). It sorts before every
module and holds the schema, the `better_supabase.blocks` table, `acting_member`,
`actor_may_write`, `raise_actor_readonly`, the column type helpers
(`as_column_type`, `try_column_type`, `value_unsupported`, `column_default`,
`import_run`), `merge_subject_refs`, `memo_get`, `memo_set` and
`replace_equivalent_triggers`, each exactly once. The file exists whenever a
module or the app tables render a schema file, and `add` writes it with any
module. Modules no longer paste these helpers, create `better_supabase`, or
create the blocks table. `schemaPreamble` creates only a module's own schema.

A module that installs before `memberships`, or a layout without it, used to
create an empty `member_organization_ids` in a `do` block that checked
`to_regprocedure` when it ran. The prelude now writes that function as plain DDL
when no memberships block is installed and a rendered file calls it. When
memberships is installed it defines the function, and the prelude never does.

`src/sql/pipeline/prelude.ts` builds the file. Doctor BS304 compares it like any
module file, and skips it when no other schema file renders.

## Alternatives considered

A prelude per schema would repeat the helpers for each module schema. A prelude
that installs the real `member_organization_ids` can't exist, because the
function reads the memberships table.

## Consequences

`better_supabase.blocks` gains its `block` column in the table definition, so
the `alter table ... add column if not exists` that an instance used is gone.
Tests that apply a module to PGlite apply the whole `renderBlocks` output, which
starts with the prelude. A render cache entry from an older generator build
still holds module files that paste the helpers; `--no-cache` or a new CLI
version replaces it.

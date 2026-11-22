# 1191: Read declared defaults from one table before the config literal

- Status: accepted
- Date: 2026-11-22

## Context

Option set items, pipeline stages, approval floors and numbering formats are
data a team edits, but the config holds them as literals, so every change is a
code change that regenerates SQL. The block functions that use them (item
seeds, stage seeds, `approval_policy`, `number_format`) are rendered from those
literals and cannot read anything the app owns.

## Decision

`better_supabase.declared_defaults` (in the prelude, `src/sql/declared-defaults.ts`)
holds one row per declared item with `kind`, `subject`, `key`, `position` and a
jsonb `value`. The kinds are `option_set_item`, `pipeline_stage`,
`numbering_format` and `approval_floor`. Clients cannot read the table. The
security definer function `better_supabase.declared_defaults_of(kind, subject)`
returns the rows as a jsonb array ordered by `position`, or null when none
exist.

Each block function asks the reader first and keeps its config literal as the
fallback, so a config without declared rows renders and behaves as before. A
declared row set replaces the literals as a whole: for option sets and pipeline
stages the seed inserts the declared items instead of the literal ones, and a
binding with a brand source reads the `subject@brand` rows first. An option set
with neither declared nor literal items fails with `OPTION_SET_DEFAULTS_MISSING`.
Approval floors resolve the exact `subject:action`, then `subject:*`, `*:action`
and `*:*`. Numbering formats are read only by entities that take their format
from a column (`formatFrom`), because other formats are baked into triggers.

## Alternatives considered

One table per kind: four tables for the same shape, and a fifth kind would need
a new table and a new prelude entry. A new block: about 40 files of
registration for a table without behavior of its own. Reading the table from
the client: it would open a second path next to the block's own functions and
their permission checks.

## Consequences

Defaults become data, so a change ships as a migration (ADR 1192) and not as a
regeneration. The fallback to the config literal keeps old configs working. The
price is one more stable function call per seed, and `approval_policy` is now
`stable` instead of `immutable`.

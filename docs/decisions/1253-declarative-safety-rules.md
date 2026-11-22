# 1253: Doctor rules for what pg-delta cannot see in schema files

- Status: accepted
- Date: 2026-11-22

## Context

pg-delta plans from the database the files load into. Statements that run later
(a `do` block, a function body, `execute`) leave no trace it can read, default
privileges without a role attach to the loading role, and `_custom/` files
reach the shadow but never the target. The Supabase CLI 3.2.0 also reserves
`_cluster/` and `_custom/` and ignores `schema_paths` under pg-delta.

## Decision

Doctor reads the project's own files under pg-delta and reports:

- BS725: a `do` block that runs DDL, `cron.schedule` in a function or `do` body,
  `alter publication` through `execute` or `format`, `alter default privileges`
  without `for role`.
- BS726: a schema named `_cluster` or `_custom`, or a case variant of the
  folder. BS727: `schema_paths` with pg-delta.
- BS728: a `_custom/` file without `-- pgdelta-migration:` or with a dangling
  path. BS729: a modeled object in `_custom/`.
- BS730: a table in a publication other than `supabase_realtime` without a
  primary key or `replica identity full`, which a Pipeline source needs.

Module files better-supabase writes are not read; ADR 1254 fixes their output.

## Consequences

Each hazard names its replacement. The rules read text with the same comment
and string blanking as BS317 and BS318, so a pg-parser based reader can replace
them later without changing the codes.

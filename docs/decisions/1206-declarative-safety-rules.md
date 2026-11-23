# 1206: Doctor rules for what pg-delta cannot see in schema files

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

BS725 reads the module files better-supabase writes too, so a generated statement of these shapes is reported with the module's name and the advice to upgrade and regenerate. BS726 and BS728 to BS730 and the pg-topo group already read every file in the tree. A `cron.schedule` inside a string literal, such as a `to_regprocedure` check, is not a call. A call in a body that first checks `to_regnamespace('cron')` or `to_regprocedure('cron.…')` is accepted: the job is optional, and a plain statement would make pg_cron mandatory. `alter publication` through `execute` has no such exemption, because the `do` block around it is also reported as DDL the rule cannot see.

## Consequences

Each hazard names its replacement. The rules read text with the same comment
and string blanking as BS317 and BS318, so a pg-parser based reader can replace
them later without changing the codes.

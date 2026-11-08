# 0500: Check scale practices in doctor from the catalog and the schema files

- Status: accepted
- Date: 2026-11-08
- Amends: 0460

## Context

The scale report traced slow imports and slow lists to a few shapes that doctor
never looked at: per-row function calls in policies, triggers that run once per
row during an import, an audit log nothing purges, redundant indexes, and
`param is null or col = any(param)` filters. The fixes for some of them (the
import guard on search triggers) land in the generated SQL on another branch, so
a rule can't assume the guard exists yet.

## Decision

- `src/cli/doctor/scale.ts` holds BS386 to BS392. Each reads the catalog
  snapshot, the schema files or both, and never needs a database, except that
  BS389 asks `cron.job` when it has one.
- BS386 flags a bare call of a volatile or PL/pgSQL function in a policy. A call
  inside `(select ...)` (the InitPlan form Postgres prints) is accepted, so a
  provider's memo helper that is volatile passes.
- BS388 finds the guard by source text (`import_run()` in the trigger function
  in the schema files) instead of by catalog, so it passes once the generated
  module has the guard and stays quiet when it can't find the function.
- BS393 reads `pg_stat_statements` with `--stats`, like BS209, and compares the
  mean of `import_upsert_batch` with a share of the role's `statement_timeout`.
- BS227 also reports `count()` without a `mode`, which counts exactly.

## Alternatives considered

Failing doctor on each shape would have turned existing apps red on upgrade, so
the rules are warnings or info. Reading trigger bodies from the catalog needs a
wider introspection query for every project, so the rule reads the schema files.

## Consequences

Each rule has a unit test, a heading on the doctor page and an entry in the
report schema. Later rules in this track (override drift, `verify_jwt`, seeds)
extend this ADR.

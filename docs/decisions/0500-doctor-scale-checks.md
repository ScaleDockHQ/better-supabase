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
- In a select policy BS386 also flags a per-row call of a function that is
  `security definer` or has a `set` clause, because Postgres never inlines it,
  so a stable SQL `can_<resource>(row)` check costs one call per row. The call
  is accepted as the `or` fallback after an `in (select ...)` set check, which
  only runs for rows outside the set. Write policies keep the narrower rule,
  since they check one row at a time.
- BS388 finds the guard by source text (`import_run()` in the trigger function
  in the schema files) instead of by catalog, so it passes once the generated
  module has the guard and stays quiet when it can't find the function.
- BS393 reads `pg_stat_statements` with `--stats`, like BS209, and compares the
  mean of `import_upsert_batch` with a share of the role's `statement_timeout`.
- BS227 also reports `count()` without a `mode`, which counts exactly.
- BS391 reads only the app's own schema files. A PL/pgSQL function that sets
  `plan_cache_mode = force_custom_plan` folds the null parameter, so the
  generated `knowledge_search` uses that instead of a second statement.
- BS394 holds an app override of a block function against the module's current
  text. The app writes `-- @bsb-override-of schema.fn <hash>` above its own
  function, where the hash is the first twelve hex digits of the SHA-256 of the
  module's function statement with its whitespace collapsed. A tagged function
  is no longer a BS369 conflict. `better-supabase upgrade` never touches an
  override.
- BS395 reads `[functions.<name>] verify_jwt = false` in `config.toml` and the
  files under `supabase/functions`, which doctor now loads as
  `DoctorContext.functionFiles`. The `mcp` function is exempt.
- BS396 and BS397 extend the seed rules: ten or more single-row inserts into one
  table in a seed file, and a data statement in an app schema file for a table a
  migration or block data file also writes.

- BS340 accepts a foreign key column that an app trigger reads or writes, the
  same rule `sameTenant.auto` applies (ADR 0430), by reading the trigger
  functions from the schema files (`sameTenantLayout` now also returns the bodies). BS398 reports such a
  trigger whose body never mentions the tenant column.
- `supabase db advisors` (ADR 0460): the installed CLI 2.122.0 lists `--db-url`,
  `--type` (`all`, `security`, `performance`), `--level` and `--fail-on`, which
  doctor passes. The JSON body was not captured against a database here, so the
  parser also accepts one lint per line, a test keeps a saved document, and an
  unknown shape still falls back to splinter at the pinned commit.

## Alternatives considered

Failing doctor on each shape would have turned existing apps red on upgrade, so
the rules are warnings or info. Reading trigger bodies from the catalog needs a
wider introspection query for every project, so the rule reads the schema files.

## Consequences

Each rule has a unit test, a heading on the doctor page and an entry in the
report schema. `supabase/tests/database/policy_index_explain.test.sql` checks
that a policy column uses its index and that `(select auth.uid())` is an
InitPlan. `null_filter_plan.test.sql` checks the 9.7 shapes: `knowledge_search`
forces a custom plan, `mark_notifications_read` does not use `is null or`, and
a generic plan of `param is null or col = any(param)` does not use the column
index. `list_notifications` still filters `subject_types` with that shape, and
its `types` filter is `coalesce` after the join, so neither is an index access.
That index stays with the large-tenant work.

`roles_many.test.sql` checks the shared fixture, which keeps one catalog role
per membership. The set of roles (`roles.many` on) is
`tests/sql/modules/membership-roles-db.test.ts`, because turning the option on
in this fixture rewrites the memberships module.

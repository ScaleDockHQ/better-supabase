# 1208: `gen` parses the rendered modules and every config SQL key

- Status: accepted
- Date: 2026-11-23

## Context

A module template that renders SQL Postgres rejects reached a migration before
anyone saw it, and `checkConfigSql` covered only `authorization.functions` and
the `{ sql }` payload columns of block events, although other config keys hold
SQL.

## Decision

- `gen` renders the installed modules through the render cache and parses each
  file with the pg-parser reader (`checkInstalledModules` in
  `src/cli/gen/rendered-check.ts`). A failure stops `gen` with the module (or
  instance) name, the file position and the statement. `gen --out` and the
  isolated run skip it. `tests/cli/schema-reader/rendered-modules.test.ts` keeps
  parsing every module in `ORDER`, and `scripts/select-tests.ts` selects it for a
  change under `src/sql/modules`, which `scripts/select-tests.test.ts` asserts.
- `configSqlFragments` lists every config key that holds SQL: the provider's
  function templates, `roleSources[].role.through.where`,
  `platformRoles.through.where`, persona and fixture role `setup`, the
  `vectorSearch` `boost`, `predicate` and `order`, `realtime.triggers` payload
  `{ sql }` values and the block event payload `{ sql }` columns. Each is parsed
  as an expression, an `order by` list or statements, with placeholders as
  identifiers, and the error names the config path.

## Alternatives considered

- Parse in `upgrade` only: `gen` is where an author edits the config, so the
  error belongs there.

## Consequences

`gen` pays one render (cached) and one parse per installed module. A key that
holds SQL and is added later must join `configSqlFragments`.

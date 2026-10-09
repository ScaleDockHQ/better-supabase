# Blocks

A block is one or more SQL modules plus, optionally, a TypeScript side under
`better-supabase/blocks/<name>`. Read `database.md` first for the fixture
workflow; this page is the checklist for a new block.

## The SQL module

- One file in `src/sql/modules/<name>.ts` exporting a `ModuleDefinition`
  with `NAMES` (logical tables, columns, options and hooks), `contract` (the
  functions the TypeScript side calls) and `build(ctx)`. Append it to
  `SQL_MODULES` in `src/sql/registry.ts`: the position is part of the file
  name, so new modules always go at the end.
- Functions live in `ctx.schema` (`better_supabase` by default), tables use
  `create table if not exists`, and no line of a schema file starts with
  `insert`, `select` or another data statement (`tests/sql/registry.test.ts`).
  Rows go in `data(ctx)` instead.
- Permissions go through the access contract: `better_supabase.can('tenant',
id, key)` in functions and `tenant in (select
better_supabase.tenant_ids_with(key))` in policies. Add the module's keys to
  `MODULE_PERMISSIONS` and `MODULE_PERMISSION_SCOPES` in
  `src/sql/modules/access-model.ts`, and to `DEFAULT_ROLES` when a default
  role should hold them.
- A table that holds a user's or a tenant's rows declares `lifecycle: {
user, tenant, purge }` (logical column names) in its `NAMES` entry, so the
  `data-lifecycle` module exports and purges it. Leave it out for secrets
  and for rows the purge must not touch.
- Events go through `ctx.record({ type, payload, subject, tenant, key, audit })`,
  which is `null;` without the `outbox` and `audit` modules, so it can stand
  alone as a statement. Never pad a helper with `|| "null;"`, and compare
  with `NOTHING` from `src/sql/shared.ts`, not `""`.
- `audit` is required: a security-relevant action passes one of the shared
  categories in `AUDIT_CATEGORIES` (`src/sql/context.ts`), and a content or
  status event passes `audit: false`. Don't call `audit_event` by hand.
  `audit_event` is revoked from `authenticated`, so the record must run in a
  `security definer` function or trigger (`recordTrigger` in `shared.ts`).
  `audit-everywhere.integration.test.ts` checks one entry and one event per
  action; add the action there.
- In PL/pgSQL, `perform` resets `found`, so `delete ...; ${record}; return
found;` returns the record's `found`. Check `found` before the record.
- A module reads another module only through `ctx.installed(name)` and
  `ctx.of(name)`, and only one it lists in `requires` or `integrates`; both
  throw for any other name. Prefer `integrates` and a helper that does
  nothing without the module (`ctx.notify`, `ctx.enqueue`,
  `ctx.entitlements`, `ctx.staff`) to a hard requirement. The matrix in
  `blocks/index.mdx` is checked against both lists by
  `tests/cli/docs-drift.test.ts`.
- Shared SQL lives in `src/sql/shared.ts`: `raise`, `canIn`, `userGrant`,
  `serviceGrant`, `serviceOnly`, `sha256Hex` and `pageSize`. Don't copy them
  into a module.
- Raise errors with an `errcode` and a `hint` such as `API_KEY_FORBIDDEN`;
  the TypeScript side passes the hint through as the `DbError` hint.
- Module functions never create temporary tables. `supabase db lint` runs
  plpgsql_check, which reports a table created at runtime as missing
  (42P01) and fails every adopter's lint; use a `materialized` CTE instead.
- Every new module installs next to every other one with the default
  config: `sql-modules.integration.test.ts` installs them all into
  `better_supabase`, and the pg-delta round trip diffs them.

## The TypeScript side

- `src/blocks/<name>/<name>.ts` holds the code and `index.ts` only
  re-exports (add the entry to `PURE_BARRELS` in `tests/entries.test.ts`).
- Calls go through a `BlockTransport` with `blockCall` from
  `src/blocks/shared.ts`, and return `AsyncResult`. Row coercers
  (`textOf`, `recordOf`, `optionalInstant`) live there too.
- Time values are `Temporal.Instant` (ADR 0005). Stripe goes through
  `src/blocks/stripe.ts` (ADR 0009).

## The subpath

`package.json` `exports` and `publishConfig.exports`, the entry list in
`tsdown.config.ts`, `tests/bundle/baseline.json` (`pnpm size`), the export
snapshot (`vitest run tests/exports.test.ts -u`, then review
`api/exports.json`), and the blocks table in both READMEs.

## Docs and tests

- A page in `apps/docs/content/docs/blocks/<name>.mdx`, listed in that
  folder's `meta.json`, a row in `blocks/index.mdx` and in the modules table
  of `blocks/sql.mdx`, and the block removed from `roadmap.mdx`.
- Unit tests for the module body (`tests/sql/modules/<name>.test.ts`) and the
  TypeScript side (`tests/blocks/<name>`), and an integration test that
  installs the module in a transaction and calls it as a user
  (`tests/integration/<name>.integration.test.ts`, with
  `tests/integration/block-session.ts`).
- A changeset.

# Blocks

A block is one or more SQL modules plus, optionally, a TypeScript side under
`better-supabase/blocks/<name>`. Read `database.md` first for the fixture
workflow; this page is the checklist for a new block.

## The SQL module

- One file in `src/sql/modules/<name>.ts` exporting a `ModuleDefinition`
  with `NAMES` (logical tables, columns, options and hooks), `contract` (the
  functions the TypeScript side calls) and `build(ctx)`. Append it to
  `SQL_MODULES` in `src/sql/registry.ts`: the position is part of the file
  name, so new modules always go at the end. A module whose table the
  subject checks of `comments` or `attachments` name sets `before:
"comments"`: it renders ahead of them and its file takes the number before
  theirs, so it still goes at the end (ADR 0025).
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
  `data-lifecycle` module exports and purges it. Secrets that only the
  tenant's purge should delete take `export: false`; `omit` lists columns
  an export leaves out. A `credential_ref` column goes in `credentials`
  (with `credentialSubject: "user"` when the ref is stored per user): exports
  leave it out and the organization purger revokes it before the purge.
  `tests/sql/credential-columns.test.ts` fails on one that isn't declared.
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
- Every outbox event type a module records is declared in `NAMES.events`
  (`ModuleEvents`): its subject collection (a kebab-case plural), the
  payload keys and `retries` when a retried call can record it again, which
  then needs a `key`. `ctx.record` throws for an undeclared type or a
  mismatch. Add the type and its data to the block's `events.ts`
  (`src/blocks/<name>/events.ts`: the map type and its `defineEvents` value),
  type the module's `EVENTS` as `ModuleEvents<NameEvents>`, and add the row
  on `extending/events.mdx`; `tests/sql/event-catalog.test.ts` and
  `tests/blocks/conformance.test.ts` check them. Names are
  `<entity>.<past_tense_verb>`, the payload is camelCase and carries
  `organizationId` when the event has a tenant. Use `memberAddedRecord`
  from `shared.ts` for `organization.member_added`.
- A module notifies users only through `ctx.notify`, never by writing
  notification rows.
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
- Hooks are named `before_<entity>_<action>` and `after_<entity>_<action>`
  (ADR 0015), declared in `NAMES.hooks` and called with `ctx.hook`. A
  mutating function of a module listed in `tests/sql/block-hooks.test.ts`
  gets both; add a new module there once it supports extension.
- A managed table that accepts app columns takes `options.extraColumns`
  through `ctx.extraColumns(table, reserved)`, which refuses names the
  module uses, and writes them with `addExtraColumns` from `shared.ts`.
- Every new module installs next to every other one with the default
  config: `sql-modules.integration.test.ts` installs them all into
  `better_supabase`, and the pg-delta round trip diffs them.

## The manifest

Every block has one `src/blocks/<name>/manifest.ts` (ADR 0029), built with
`defineBlock` and exported as `<camelName>Block` from the block's `index.ts`,
and listed in `src/blocks/registry.ts` and `tests/blocks/all-blocks.ts`. A
block with only SQL gets a directory with just the manifest (and
`events.ts` when it records events).

- `sql` lists the SQL modules it installs; every module belongs to exactly
  one block. `options` holds `optionKeys([...])` per module, matching
  `NAMES.options`.
- `events` is the block's own map from `events.ts`. Never add a type to a
  shared map in core.
- `consumes` and `provides` name ports from `src/blocks/ports.ts`
  (`notifier`, `files`, `attachments`, `workflows`, `sink`). A block reaches
  another block only through a consumed port: never import or call a
  sibling's creator. A new port goes in `BlockPorts` and the `createBlocks`
  port list, with a row on `blocks/create-blocks.mdx`.
- `create` is the creator itself, `create<Name>`, so the conformance test
  can read its name. Options a sibling used to need (a notification type, a
  sink's events) are the creator's own options, set with `.with(...)`.
- `category` and `recipes` feed the catalog and `/recipes`
  (`scripts/build-catalog.ts`, `scripts/build-recipes.ts`).

`tests/blocks/conformance.test.ts` checks the contract over every manifest,
with allowlists of today's exceptions. Fix a block to take it off a list;
never add a new block to one.

## The TypeScript side

- `src/blocks/<name>/<name>.ts` holds the code and `index.ts` only
  re-exports (add the entry to `PURE_BARRELS` in `tests/entries.test.ts`).
- Calls go through a `BlockTransport` with `blockCall` from
  `src/core/block-helpers.ts` (re-exported by `src/blocks/shared.ts`), and
  return `AsyncResult`. Row coercers (`textOf`, `recordOf`,
  `optionalInstant`, `enumOrThrow`), `mappersOf`, `pageOf` and
  `injectableOf` live there too; don't copy them into a block.
- Options use `mappers` for error mappers and `{ limit, cursor }`
  (`CursorPageOptions`) for pages. An injectable function or object takes an
  optional `apiVersion: 1`, checked with `injectableOf`, and gets a kit in
  `src/testing/injectables.ts`.
- Extension (ADR 0015): the client returned by the creator is wrapped with
  `withBlockHooks(client, options.hooks, { block })`, and the options take
  `hooks?: NoInfer<BlockHooks<Client>>`. A block whose rows carry app
  columns takes a Standard Schema `fields` option and reads and writes them
  through `blockFields` (`src/core/block-fields.ts`), so a bad write is a
  `validation` error and a read is parsed. Internal calls between methods
  go through the hooked client, so hooks see them. Never redefine the
  extension helpers per block; re-export them from the block's `index.ts`.
- Time values are `Temporal.Instant` (ADR 0005). Stripe goes through
  `src/blocks/stripe.ts` (ADR 0009).

## Client state

- A block with UI state has a controller in `src/blocks/<name>/client.ts`
  built with `defineController` (ADR 0030). It takes the block client (or a
  `Pick` of it), `auth` and the ports it needs, and imports no React, DOM
  or React Native code; `tests/blocks/platform-neutral.test.ts` checks the
  whole import closure, so don't name a local `window` or `document` either.
- A platform need is a port in `src/client/ports.ts` with a web default in
  `src/client/web-ports.ts` and a native one in `src/client/native/ports.ts`.
  Native defaults take Expo modules structurally, never by import.
- The `/react` hook builds the controller with `useController` from
  `src/blocks/react-controller.ts`, passes callbacks through `useLatest`,
  and turns an input that changes often (a range, the subjects on screen)
  into an action such as `setRange` instead of a new controller.

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

# Blocks

A block is one or more SQL modules plus, optionally, a TypeScript side under
`better-supabase/blocks/<name>`. Read `database.md` first for the fixture
workflow; this page is the checklist for a new block.

## The SQL module

- One file in `src/sql/modules/<name>.ts` exporting a `BlockSqlDefinition`
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
- A module that stores rows per subject (a `subject_type` and `subject_id`)
  renders `subjectMergeHandler` with `moveSubjectRows` from
  `src/sql/subject-merge-sql.ts`, so record merges move its rows (ADR 0072).
  A block that merges its own records renders `recordMergeFunction`.
- Permissions go through the scope port, never the access contract by name:
  `ctx.scope.can(id, key)` in functions, `ctx.scope.check(column, key)` in
  policies, `ctx.scope.ids(key)` for the set of scope ids, `ctx.scope.canUser`,
  `ctx.scope.platform`, `ctx.scope.members()`, and `ctx.scope.guest(tenant,
  type, id, action)` or `ctx.scope.guestParty(tenant, type, id)` to let guests
  in, or-ed onto the member check with `guestOr` (`false` without guests, ADR
  0070). In `tenant` scope they render
  the access contract (`can`, `tenant_ids_with`, `is_platform`);
  `tests/sql/scope.test.ts` fails on a literal call in `src/sql/modules`. A
  module that needs tenants declares `scopes: ["tenant"]`. One that runs per
  user or in one shared space uses `ctx.scope.column()` for its scope column,
  `ctx.scope.bind` or `ctx.scope.value` for scope id arguments, and
  `ctx.scope.eq` to compare scope ids, and gets golden files under
  `tests/sql/__golden__/scope-*`.
- Name module functions, triggers, indexes and policies through `ctx.fn`,
  `ctx.trigger` or `ctx.naming.rename(...)`, never a literal that contains
  `organization` or one of the module's entity nouns, so
  `blocks.memberships.entities.organization` and `blocks.<name>.entities` rename
  them (`tests/sql/__golden__/naming-workspace`,
  `tests/sql/entity-renames.test.ts`). Name a table's index or policy after
  the table (`${ctx.tableName("comments").name}_read`), so it follows the
  rename. Parameter names stay, and so do block-scoped names that start with
  `bs_<block>_` (constraints, storage policies, settings) and storage paths,
  because renaming them would orphan the old objects or files. Add the module's keys to
  `MODULE_PERMISSIONS` and `MODULE_PERMISSION_SCOPES` in
  `src/sql/modules/permissions-model.ts`, and to `DEFAULT_ROLES` when a default
  role should hold them.
- Every entity a user can rename goes in `NAMES.entities` (ADR 0060): its
  table, its `singular`, `primary: true` for the one a bare string renames,
  and `subject` when it registers as a subject. Event types, hooks, payload
  keys and client methods derive from the singular, so a rename reaches all
  of them; `tests/core/entity-naming.test.ts` and
  `tests/sql/resolved-names.test.ts` cover the renamer.
- `upgrade` renames an installed block's objects when its entities
  change (`src/sql/entity-upgrade.ts`): it renders the module under both
  names and pairs the created objects by position, so a module whose object
  list depends on the entity name gets refused. Keep the order of created
  objects independent of names. A table or column a release renames goes in
  `NAMES.migrations` (`from`, `table`, `was`, `columns`) instead of a
  hand-written upgrade step, so the rename follows the app's config.
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
  (`BlockSqlEvents`): its subject collection (a kebab-case plural), the
  payload keys and `retries` when a retried call can record it again, which
  then needs a `key`. `ctx.record` throws for an undeclared type or a
  mismatch. Add the type and its data to the block's `events.ts`
  (`src/blocks/<name>/events.ts`: the map type and its `defineEvents` value),
  type the module's `EVENTS` as `BlockSqlEvents<NameEvents>`, and add the row
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
- Shared SQL lives in `src/sql/shared.ts`: `raise`, `userGrant`,
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
  A write that takes them as a separate argument uses `extraFieldsArg`
  from `shared.ts` for it: the parameter is always `fields jsonb default
  null`, and `drop` goes before the function so turning `extraColumns` on
  or off never leaves two overloads (`tests/sql/extra-fields-overloads.test.ts`).
- Every new module installs next to every other one with the default
  config: `sql-modules.integration.test.ts` installs them all into
  `better_supabase`, and the pg-delta round trip diffs them.

## The manifest

Every block has one `src/blocks/<name>/manifest.ts` (ADR 0029), built with
`defineBlock` and exported as `<camelName>Block` from the block's `index.ts`,
and listed in `src/blocks/registry.ts` and `tests/blocks/all-blocks.ts`. A
block with only SQL gets a directory with just the manifest (and
`events.ts` when it records events).

- Code several blocks share but that has no SQL module of its own (money
  and the providers in `src/commerce`) lives outside `src/blocks`, which
  holds only blocks.
- `sql` lists the SQL modules it installs; every module belongs to exactly
  one block. `options` holds the module's schema from the block's
  `options.ts` (`blockOptions`), with one `option.*` per key in
  `NAMES.options`, and `src/blocks/options-registry.ts` lists it. Mark an
  option `client: true` when the TypeScript side reads it too: `gen`
  writes it to `blocks.generated.ts` and `defineBlocks` passes it to the
  creator. Run `pnpm --filter better-supabase gen:config-schema` after a
  change, which rewrites `schemas/config-v1.json`.
- `events` is the block's own map from `events.ts`. Never add a type to a
  shared map in core.
- `schemas` holds a Standard Schema `input`, `change` and `listFilter` per
  entity from the block's `schemas.ts`, built with `entitySchema`.
  `tests/blocks/entity-schema.test-d.ts` checks each one agrees with the
  client's types, and `renameBlock` renames their keys.
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

## Record sections

- A block that owns part of a record page declares it with `defineSection` in
  `src/blocks/<name>/section.ts` and puts it on the manifest's `sections`.
  Section names are global across the app; on a clash the first block wins,
  so name a section after the block.
- A section write (`writes.<name>`) takes `{ input, run, permission? }`. Its
  input is a schema of plain JSON: `recordServer` exposes it as a Server
  Action, so a Temporal value or a class can't cross it.
- `pnpm catalog` records each section's writes in the catalog, and
  `gen` reads them to name the generated actions (`<write><Type><Section>`).
  Add a write, then run `pnpm catalog` and the features golden test
  (`tests/cli/gen/features.test.ts`).
- A section whose block needs more than the transport (attachments needs
  `storage`) gets it from the shared options `recordServer` and
  `createRecordProvider` pass to every client. Add new needs there, not as a
  custom action in an example.

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

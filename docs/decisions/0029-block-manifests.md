# 0029: Describe every block with one manifest, wired by what it provides and consumes

- Status: accepted
- Date: 2026-10-15

## Context

Blocks combine well at the import level (37 edges between blocks, no
cycles), but the code around them knows every block by name:

- `src/blocks/create-blocks.ts` wires siblings by hand: the
  `aiTaskNotification`, `reminderNotification` and `metricEvents` options,
  the `files`, `notify` and `notifyDelivery` slots, the `aiFiles` special
  case and `sinks: { search, metrics }`.
- `src/core/block-events.ts` holds one closed `BlockEventMap` of every
  block's events, so a new block edits core.
- `drive` and `workflow-builder` build their own `attachments` and
  `workflows` clients, which `createBlocks` hooks never reach.
- A block is configured twice: its SQL half under `sql.modules.<name>` and
  its client options in TypeScript, kept in sync by hand (`drive.ts` says
  `requireScan` must match the SQL option).
- Extension points differ per block: `fields` on 2 blocks, `extraColumns`
  on 3, `hooks` on 19 of 67, and four blocks skip `blockCall`.

Presets (ADR 0031) only work when any set of blocks combines without code
that names them, so the block itself has to say what it needs.

## Decision

Each block exports one manifest built with `defineBlock` (for example
`src/blocks/comments/manifest.ts`). It names the block's SQL modules, its
options schema (a Standard Schema), its own event map, what it `consumes`
and `provides` (ports such as `notifier`, `files` or a sink), its creator,
its headless controller (ADR 0030), its category and its UI recipe slugs.

- `createBlocks` wires on `provides` and `consumes`, never on block names.
  Sibling-specific options move into the manifests that need them:
  `notifications` provides `notifier`, `search` and `metrics` provide
  sinks, `drive` consumes `attachments` and `workflow-builder` consumes
  `workflows`, so no block creates a hidden sibling client.
- Events are declared per block. `BlockEventMap` becomes the union
  inferred from the manifests passed to `defineBlocks(...)`, so the types
  still come from an inferring call and not from `declare module`
  (invariant 2), and an app adds its own with `defineEvents({...})`.
- The config key for blocks is a top-level `blocks`, replacing
  `sql.modules`. After the manifests a block's config covers both its SQL
  options and the options its client takes, so it no longer belongs under
  `sql`. `sql` keeps the SQL-wide settings (`schema`, `api`, `scope`,
  `naming` and the paths), and the foundation modules (`tenant`, `access`,
  `updated-at`, ...) become blocks in a `foundation` category. `SqlModule`
  stays the internal name of a block's SQL half.
- A directory in `src/blocks` is a block and has a `manifest.ts`. Code
  that blocks share but that installs no SQL module of its own lives
  outside `src/blocks`: money and the payment and tax providers are
  `better-supabase/commerce` (`src/commerce`), which catalog, orders,
  inventory and promotions import.
- Every block follows one contract, checked by
  `tests/blocks/conformance.test.ts` over the manifests: the creator is
  `create<Name>(options)` taking `BlockOptions`, it accepts `hooks`, every
  managed table takes `fields` and `extraColumns`, every call goes through
  `blockCall`, it has its own event map, it creates no sibling client, and
  its controller imports no DOM or React Native globals. The test starts
  with an allowlist of today's exceptions that shrinks to zero; outliers
  are renamed without aliases (`createBuilder` becomes
  `createWorkflowBuilder`, `createPushDevices` becomes `createPush`).

The project is greenfield, so `sql.modules`, the sibling-specific
`createBlocks` options and the closed `BlockEventMap` are removed in the
same release, with no shims, codemods or migration guide.

## Alternatives considered

- **Keep `sql.modules` and add a `blocks` key next to it.** Two keys for
  one thing is the drift this decision removes, and "modules" disagrees
  with the docs, the subpaths and ADR 0012.
- **`sql.blocks`.** A block's config is no longer only SQL once the client
  options join it.
- **Keep `BlockEventMap` closed and generate it.** Generation would still
  route every new block through core, and app events would stay impossible.
- **Wire siblings by name in a registry table.** It moves the hard-coding
  instead of removing it, and a preset with a block the table doesn't know
  would fail at runtime.

## Consequences

A block can be added, removed or replaced without touching
`create-blocks.ts` or core, which is what presets and `better-supabase add`
need. The inferred event map makes `typecheck:perf` a gate for this change.
Every block's creator, options and docs move in the same release, which is
a large diff, and an app that passed the old options must change its code.
Revisit if a port needs more than one provider at a time in one app (two
notifiers), which the provides/consumes model resolves to one.

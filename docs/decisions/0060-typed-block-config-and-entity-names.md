# 0060: Name block entities per block, with typed config keys and automatic subjects

- Status: accepted
- Date: 2026-10-21

## Context

Blocks own their nouns: work-items has `work_items`, `create_work_item`,
`work_items.read`, `work_item.created` and `WorkItem`. An app that calls them
tasks could rename tables and columns through `blocks.<module>.tables` and
`columns`, but functions, permission keys, events, hooks, subjects and the
TypeScript client kept the default noun. The tenant had its own rename
(`sql.naming.tenant`) with a separate code path. Block subjects came from five
hand-called helpers (`workItemsSubjects()` and others) that apps had to keep
in sync with the block config. The keys under `blocks.<module>` were typed as
loose records, so a typo in a table or function name only failed at render
time.

## Decision

Each block declares the entities it can rename in its manifest and SQL
module (`ModuleNames.entities`: table, singular, plural, primary, subject
settings). `blocks.<name>.entities` renames them, as a string for the
primary entity or per entity with `{ name, plural, url, subject }`.
`src/core/entity-naming.ts` renames every case form of a noun, and
`resolveNames()` turns the config into one `ResolvedNames` per module that
the SQL context, `gen`, doctor and the subject registry read.

- **SQL:** tables, columns, functions, index, policy and trigger names,
  event types and payload keys, permission keys (and the default roles),
  hook targets and number sequence keys follow the rename. Function
  parameter names, error hints and messages keep the default nouns. Files
  carry an `@bs-entities` line, and `sql upgrade` refuses a changed rename on
  an installed block.
- **Tenant:** `sql.naming` is removed. The tenant name is the tenant block's
  `organization` entity (`blocks.tenant.entities.organization`). It renames
  SQL identifiers, while events, permission keys, hooks and JSON keys keep
  `organizationId`.
- **Subjects:** installed blocks register their entities in
  `config.subjects` under the renamed type. `subject: false` opts one out,
  and a `config.subjects` entry with a block's type is an error. The five
  `*Subjects` helpers are deleted.
- **TypeScript:** `renameBlock(block, names)` renames a client's methods,
  argument and result keys, events, hooks, input schemas and `invalidates`
  map, and `RenamedClient` does the same in the types. `blockNames` wraps the
  transport so the block code keeps reading its default names. `gen` writes
  `tasksBlock = renameBlock(workItemsBlock, ...)` and type aliases (`Task<F>`)
  into `blocks.generated.ts`, without `declare module` (invariant 2).
- **Typed keys:** `BlockConfig` types `tables`, `columns`, `functions`,
  `permissions`, `hooks` and `entities` from `BlockNameRegistry`, which
  `pnpm catalog` generates from `SQL_MODULES`. `defineConfig<const C>`
  returns the literal config so references between keys (app table targets,
  bucket names, role names) are checked.

The manifest field is optional, so `apiVersion` stays 1 (invariant 10).

## Alternatives considered

- Keep table and column overrides only. They leave every other name with the
  default noun, which is the problem.
- Deprecated wrappers for `sql.naming` and the `*Subjects` helpers. The
  package is pre-1.0 and the changeset lists each old key next to its
  replacement, so one migration step is cheaper than two code paths.
- Rename event payload keys for the tenant too. Every block reads
  `organizationId`, and the clients, AsyncAPI documents and sinks would all
  need a second key set for a name that only matters in SQL.
- Generate the client types with `declare module` augmentation. Invariant 2
  forbids it; `renameBlock` carries the types through inference.

## Consequences

An app renames a block's noun in one place and gets matching SQL, events,
permission keys, subjects and client types. Renaming an installed block is
refused rather than migrated; a migration that renames existing tables is a
follow-up. Every new block module with nouns must declare `entities`, and
the SQL sweep test (`tests/sql/entity-renames.test.ts`) fails on any default
noun a rename leaves behind. One renamed work-items client costs about 60%
more type instantiations (65,783 to 104,898); we revisit the template-literal depth if the type
benchmark regresses.

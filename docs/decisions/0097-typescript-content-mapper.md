# 0097: Serve the schema types through a TypeScript 7.1 content mapper

- Status: accepted
- Date: 2026-10-24

## Context

`better-supabase gen` writes the schema types as files: `generated.ts` and the
`database.types.ts` that `@supabase/postgrest-typegen` renders. On a 250-table
schema they come to about 1.4 MB, which apps commit or regenerate, and which
drift from the schema until someone runs `gen` again.

TypeScript 7.1 adds content mappers
([microsoft/typescript-go#4712](https://github.com/microsoft/typescript-go/pull/4712)):
a package names a process under `typescript.contentMapper` in its
`package.json`, a project lists it in `contentMappers` with the file
extensions it handles, and `tsc` asks that process for the TypeScript text of
each such file. `tsc` runs it only with `--runExternalCode`, and an editor
only in a trusted workspace. [reylo](https://github.com/colinhacks/reylo)
uses this to type schema files without a build step.

7.1 is a beta (7.1.0-beta). The toolchain reference never installs the
pre-release of a minor, and `oxlint-tsgolint` has no 7.1 build, so the
repository can't move to it.

## Decision

`gen.contentMapper: true` turns on mapper mode; files mode stays the default
and its output is byte for byte what it was. In mapper mode `gen` writes a
slim `generated.ts` (the runtime values and `export type * from
"./schema.bsb"`), a one-line `schema.bsb` marker next to it, and no
`database.types.ts`. `init --content-mapper` sets the option and adds the
`contentMappers` entry and `--runExternalCode` where it can edit the files.

The mapper is `dist/mapper/bin.js` (`src/mapper`), registered in the package's
`package.json`. It speaks protocol 1, pinned as
`SPEC_PINS.typescriptContentMapper`. `openProject` loads the config and the
snapshot and renders the types module through `cachedTypesModule`, the same
cache `gen` uses (`node_modules/.cache/better-supabase/types-<key>.json`);
`transform` returns that text with one span that maps the whole file. Its
`watchedFiles` are the config, the snapshot, `supabase/config.toml` and a
stamp file that `gen` rewrites only when the types key changes, all as real
paths (TypeScript doesn't follow a symlinked directory such as macOS `/tmp`).
`tsc` closes and reopens the project when one changes, so every `openProject`
loads fresh instead of sharing a loaded project across handles.

The mapper never throws. When the source fails it serves the last rendered
types and reports BS604; with nothing to serve it returns an empty module and
BS603. BS605 marks a `.bsb` file other than the one `gen` writes, and BS606 an
option the mapper doesn't read. Doctor's BS602 reports a missing
`contentMappers` entry, a TypeScript older than 7.1 and a `typecheck` script
without `--runExternalCode`.

The toolchain stays on TypeScript 7.0.2. The `ts71` catalog pins
`7.1.0-beta` for two consumers only: `tests/types/ts-7.1`, which type-checks
the shared consumer on 7.1 and checks that both modes give identical types,
and the type benchmark. This is a scoped exception to "never install the
pre-release"; it ends when 7.1 ships stable with a tsgolint build, and the
default catalog moves as `docs/agents/tooling.md` describes.

## Alternatives considered

- **Files only.** Kept as the default, but every app keeps committing or
  regenerating the type files.
- **Map the SQL in `supabase/schemas` directly.** The mapper would need a
  Postgres parser or a database inside the `tsc` process, and the migrations
  and introspected sources wouldn't fit. Mapping the snapshot keeps one
  source of truth with `gen`.
- **Map the config file.** `tsc` already owns `.ts` files, and the types
  depend on the snapshot, not only the config.
- **Move the whole toolchain to the beta.** tsgolint refuses a mismatched
  compiler, and the toolchain reference forbids it.
- **Share a loaded project across handles.** A reopen after a watched change
  has to see the new inputs; the cache already makes a fresh load cheap.

## Consequences

The schema types stop being files in the repository, and they follow the
snapshot in the editor without a manual `gen`. The types are the same in both
modes (`tests/types/ts-7.1/equal.ts`). Each `tsc` run starts the mapper,
about 0.3 s on the benchmark machine; checking costs the same as files mode.
Apps need TypeScript 7.1, a trusted workspace and `--runExternalCode` in CI,
and a change to `supabase/schemas` reaches the editor through `gen` or
`gen --watch` (globs can't be watched), which rewrites the stamp. A new
protocol version needs a new pin and a check of the handlers; a stable 7.1
retires the `ts71` catalog.

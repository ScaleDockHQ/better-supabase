# 0248: Split the generator into stages and cache renders

- Status: accepted
- Date: 2026-11-06
- Amends: 0247

## Context

ADR 0247 measured `upgrade` and found it renders every module on every run
(a warm no-op renders 75 modules). `render.ts` mixed the pure steps (naming,
scoping, guards) with file layout, and each command that needs the rendered
files (`upgrade`, `sync`, `doctor`, `powersync`, the app table files) rendered
them again. Doctor had its own SQL statement splitter, so nothing else could
share it.

## Decision

`src/sql/pipeline/` holds the pure stages: `split` (statements of a file),
`model` (the declared objects of every schema file, each with its owner, a
module or an app file, and a parse cache keyed on the content hash and a parser
version), `resolve`, `prepare` (the module SQL after naming, tenant scope and
actor guards), `checks` (the render-time errors), `assemble` (headers, the
`better_supabase.blocks` row) and `render-key`. `render.ts` only orders them.
`src/sql/emit/` holds statement builders; `emit/check.ts` writes a range inside
a check as `x >= a and x <= b`, which a schema diff re-parses stably.

`src/cli/sql/render-cache.ts` is the only I/O. `renderBlocksCached` keys the
rendered files on the block names, the layout and the CLI version, keeps them
in memory for the process and in one file under
`node_modules/.cache/better-supabase/render-blocks.json`, and discards a disk
entry when any file's `@bsb-hash` line no longer matches its body. A layout
that holds a function can't be keyed and renders fresh. `--no-cache` on
`upgrade` and `sync` renders again and leaves the cache alone.

Doctor BS369 reports an object that a module file and an app file both create,
and BS370 reports `-- pg-delta: transaction=false` in a schema file. Both read
the model.

The test task of `packages/better-supabase` now lists every repository file the
tests read outside the package (the docs content, `supabase/schemas`, the
snapshot, the recipes, `AGENTS.md`), so a change to one of them no longer
reuses a cached passing run.

## Alternatives considered

A cache per module keyed on the objects it read needs a read-tracking model
that the modules do not use yet, so it stays open. A worker pool cannot help
until the render is split per module, because one `renderBlocks` call is one
unit of work.

## Consequences

Still open, in this order: the prelude file, static DDL (no `if not exists`,
no `do` blocks that create objects), the per-module render cache with read
tracking, `dev` watch and the worker pool, and the naming renames of ADR 0247.
The model is not yet used by `renderBlocks`, so the audit tables file still
needs its second pass.

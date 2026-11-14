# 0990: Keep the workflow canvas recipe as the minimal editor

- Status: accepted
- Date: 2026-11-14

## Context

`workflow-canvas.tsx` and `node-panel.tsx` feed the `workflow-canvas` recipe
(`scripts/recipes/sources.ts`) and are knip entries. The full editor in
`workflow-editor.tsx` covers the same ground with undo, validation, versions
and a run panel, so the two overlap (finding EX-210).

## Decision

The recipe stays the small starting point: one file a reader copies to get a
canvas that saves, publishes and runs. The full editor is the example's page
and is not a recipe, because at about 700 lines with its panels it is not a
single copyable file. The knip entry comment says so. No shared code is
extracted, since a recipe must work as one copied file.

## Alternatives considered

Pointing the recipe at `workflow-editor.tsx`: the recipe page would show 700
lines and pull in eight sibling files. Deleting the recipe: the docs page and
the block manifests name it.

## Consequences

The two files can drift. The `workflow-canvas` recipe is built from the
example on each `pnpm recipes` run, and its type check keeps it compiling.

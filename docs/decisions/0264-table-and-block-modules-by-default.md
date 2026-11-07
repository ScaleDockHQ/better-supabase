# 0264: Write table and block modules by default

- Status: accepted
- Date: 2026-11-07
- Amends: 0262, 0263

## Context

0262 and 0263 wrote one module per table and one slice module for the block
config, behind `gen.tableModules` and `gen.blockModules`. Only the Next.js
example turned them on. The other layout kept every table in the schema object,
so a page that imported the generated module shipped all of them.

## Decision

Both options default to `true`; `false` keeps the single module.

- `gen` writes `tables/<table>.ts`, `generated-schema.ts`, `clientSchema`,
  `blocks/slices.ts` and `blocks/permissions.ts` without any config.
- `schema` is exported from `generated-schema.ts`, not `generated.ts`. `init`
  writes that import, and falls back to `generated.ts` with `--content-mapper`.
- `gen --metadata` output and the content mapper keep the single module, as
  before, so `--emit` still prints one file.
- `better-supabase codemod table-modules` moves an existing project: it
  imports `schema` from `generated-schema`, and in a `"use client"` file turns
  `bsb.db.customers` into `bsb.table(customersTable)` with the import. A
  `queries.<table>` read is listed for a hand change. The codemod reads the
  table modules `gen` wrote, so run `gen` first.
- The runtime test fixtures (`tests/fixtures/generated*.ts`) and the type
  benchmark's `tests/types/shared` keep the single module: they exercise the
  runtime and the type cost of one schema object, and a layout change would
  move the type baselines without testing anything new. The default layout is
  covered by `render.test.ts`, the generated examples and the validation
  projects.

## Not done

0263 left the per-instance block interfaces open. `RenamedType` aliases and the
per-instance client factories stay in `blocks.generated.ts`: they need the block
API types written out per instance, and `gen` has no type extraction step to
read them from the block sources. They are type-only, so they cost nothing at
runtime. A browser client that needs one instance's typed controller imports
that type with `import type`.

## Consequences

The Next.js example already used the layout, so its `next build` baseline is
unchanged (no route grew or shrank). The other examples and the validation
projects regenerate into the new layout, and the Vite example still builds its
client over the full `schema`, so it ships every table until it moves to
`clientSchema`.

An app that imports `schema` from `generated.ts` fails to compile after
`gen`. The migration guide and the codemod name the change.

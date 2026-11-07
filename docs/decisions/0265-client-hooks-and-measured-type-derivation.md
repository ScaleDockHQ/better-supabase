# 0265: Read tables in every framework's hooks, name AppDb, and keep Insert and Update written out

- Status: accepted
- Date: 2026-11-07
- Amends: 0262, 0264

## Context

With table modules on by default, the generated `hooks.ts` passes each table
module to `defineListHook` and `defineOneHook`. Only the React hooks took it, so
a Vue, Solid or Svelte app got a type error from the generated file. The plan
also asked for `Insert` and `Update` derived from `Row`, a named `AppDb`
interface, and a check that client files stay off the generated barrels.

## Decision

- The Vue, Solid and Svelte hooks take the table module and read through
  `client.table(module)`, as the React ones do.
- `hooks.ts` exports `interface AppDb extends DbOf<typeof betterSupabase> {}`
  in place of a type alias, so every hook resolves one named type.
- Doctor BS621 warns when a `"use client"` file imports `generated-schema`,
  `blocks.generated` or `blocks.config`. It runs on every project and so on the
  Next.js example, whose `doctor` task is part of `pnpm verify`. It is off with
  `gen.tableModules: false` and in content mapper mode.
- `Insert` and `Update` stay written out.

## Measured and not done

`InsertFromRow<Row, Optional, Generated>` and `UpdateFromRow<Row, Generated>`
derive both types from a `Row` alias, and `gen` wrote them in place of the two
copies of the columns. The generated file shrank, and the type benchmark failed
its 10% gate: on the 150-table profile TypeScript 7 went from 40,130 to 89,191
instantiations and 17,560 to 21,436 types, and on the CentraKit profile from
50,328 to 132,862 instantiations. A mapped type per table and verb costs more
than the lines it replaces, and every conditional type that reads `Insert`
instantiates it again. The change was reverted. The text of `Insert` and `Update`
is the cheaper form, and it compresses well because the three copies repeat.

## Consequences

Vue, Solid and Svelte apps load one table per page like the React ones. `AppDb`
is importable from `hooks.ts`, so an app no longer needs its own alias.

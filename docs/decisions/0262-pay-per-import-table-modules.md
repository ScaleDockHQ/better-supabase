# 0262: Write one module per table and register the tables a client uses

- Status: accepted
- Date: 2026-11-07
- Amends: 0232

## Context

A generated schema is one object. `generated.meta.js` lists every table, so a
client page that imports `bsb` ships all of them, and `app.ts` builds the whole
schema, the extensions and the server's `app` in one module. A bundler removes
exports and PURE-annotated calls; it does not remove one property of an object.
The `next build` baseline shows the cost: the `customers` route loaded 3.0 MB of
JavaScript because `lib/lists.ts` imported the server's `betterSupabase`, and
every route carried the 19 tables of the example.

## Decision

`gen.tableModules: true` writes `tables/<table>.ts` next to the generated
module. Each file is one annotated call, `defineTable({...})`, and exports
`<key>Table` (`customersTable`). The metadata module keeps everything else and
lists no table. The generated module no longer holds the server's schema:

- `generated-schema.ts` imports the metadata module and every table module and
  exports `schema`, with a PURE annotation. Only server code imports it.
- `generated.ts` keeps the types, the value lists, `buckets`, `topics`, the
  extensions (now exported) and a new `clientSchema`: a schema with
  `lazyTables: true` and no tables.
- `hooks.ts` passes each table module to `defineListHook` and `defineOneHook`,
  which read through `client.table(module)`.

A schema with `lazyTables` registers tables when something uses them.
`BetterSupabase.registerTable` adds the table to the definition and to every `db`
made earlier, `bsb.table(customersTable)` returns the repository of a module
(and `db.<table>` when the schema lists its tables), and `defineListQuery`
accepts a table module in place of a table name. `defineSchema` copies `tables`
for a lazy schema, so registering never changes a module's constant. A table you
embed with `with` has to be registered too: import its module and pass it to
`bsb.table` first.

Records import `permissions` from `blocks.config.ts`, which holds plain data,
instead of `blocks.generated.ts`, which imports every installed block.

The layout is opt in. Stdin mode (`--stdout`) and the content mapper keep the
single-module output, so fixtures, the other examples and the mapper do not
change. The Next.js example turns it on: `client-app.ts` builds the browser's app
over `clientSchema`, `app.ts` the server's over `schema`, and `lib/lists.ts`
defines the customers list over `clientApp` and `customersTable`.

The hooks stay in `hooks.ts`, not in the table modules as the plan sketched: a
`"use client"` module that the server imports for its metadata would turn into a
client reference.

## Alternatives considered

- Resolve relations through a thunk in each table module. Importing the target
  module pulls the related tables of every table, so one page loads the graph.
- Copy the target's columns into each relation. Nested embeds would lose their
  metadata, and every table would carry its neighbours.
- A `Proxy` on `db` that registers on first read. The type of `db` still lists
  every table, and a read in a render path would register a table nobody
  imported.
- Rely on `/*#__PURE__*/` and `sideEffects: false` alone. Turbopack keeps a
  module's other exports once one is used, with or without
  `turbopackRemoveUnusedExports`, so the schema had to move to its own module.

## Consequences

A page's bundle holds the table modules it imports. On the Next.js example every
route sheds the 19 tables and `customers` sheds the server's whole index
(-1.2 MB raw). `tests/next-build` gains an assertion that the customers route has
`customersTable` and no other table, and that no route loads `generated-schema`.

A browser client on `clientSchema` has no `bsb.db.<table>` and no
`bsb.queries.<table>` for a table nothing registered; a client file registers the
table first. The codemod that rewrites `bsb.db.customers` to the table import is
not written yet, and neither are the per-instance block modules, the removal of
`RenamedType` and the shared `generated.meta.js` split: this ADR covers the
table half of the layout. The default stays the single module until `init`, the
fixtures and the record recipes move to the new one.

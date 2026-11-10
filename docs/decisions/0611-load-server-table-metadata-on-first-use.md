# 0611: Load server table metadata on first use

- Status: accepted
- Date: 2026-11-10
- Amends: 0262

## Context

Table modules (ADR 0262) keep table metadata out of the browser. The server
schema module still imported every table module and `generated.meta.js` at
start. An app with 273 tables shipped about 800 KB of table metadata and 147 KB
of function metadata into every server trace, including routes that read one
table.

Repository builders read a table's metadata while they build a query, and that
build happens inside the async call that runs the query. A loader can therefore
resolve the module before the query is built, as long as the first touch of an
unregistered table is inside that async run.

## Decision

With `gen.tableModules` on (the default), the generated server schema passes
`lazyTables: true` and `tableLoaders`. Each loader is `() => import("./tables/<table>.ts")`.
`defineSchema` registers a table the first time a repository asks for it, and
waits for that loader. Function metadata moves to `generated.functions.js` and
loads on the first `rpc` call. `gen.serverTables: "eager"` keeps the previous
module, which imports every table.

## Alternatives considered

- Per-route registries (`server-tables/<group>.ts`). An app would still have to
  name the group on each route. Loaders follow the tables the route already
  imports through its queries, without a second list.
- A dynamic `import()` of `generated.meta.js` from the eager schema. The module
  graph would still trace every table, because the schema imported them all.

## Consequences

A server function evaluates the table modules it touches, not the whole schema.
The first call to a table pays for that module. `gen.serverTables: "eager"` is
the escape hatch. Upgrading from 0.54 already removes tables from the client
trace, because table modules shipped in 0.57.

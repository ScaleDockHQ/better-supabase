# 0855: Stream a CSV export over the page filters

- Status: accepted
- Date: 2026-11-14

## Context

EX-1210 found export on eight blocks, each with its own options and its own
route. An export that reads other filters than the list shows is wrong by
construction, and a route per block repeats the streaming code.

## Decision

`src/core/entity-export.ts` adds `exportCsv(page, options)`, a
`ReadableStream<string>` that calls `page` with the same `q`, `filters` and
`sort`, follows `nextCursor`, writes the header once and one CSV chunk per page,
so memory stays at one page. `columns` fixes the header, `maxRows` (default
100,000) caps the file, and a page that fails or a cap that is reached errors the
stream with a `DbException` (hint `EXPORT_ROW_CAP` for the cap). Spreadsheet
formula text is escaped as in `toCsv`. `exportResponse(page, filename, options)`
is the route: `text/csv`, `Content-Disposition`, `no-store`. `entityList` returns
`export(options)` beside `page`, `facets` and `count`, and a manifest entity can
declare `export: true | { columns, maxRows }`.

## Alternatives considered

- Build the whole CSV in memory: large tenants would run out of memory.
- A separate export SQL function: it would drift from the filters of `page`.

## Consequences

An export always matches the list. A block that writes its own `page` calls
`exportCsv` with it. Blocks with their own export keep it until their lane.

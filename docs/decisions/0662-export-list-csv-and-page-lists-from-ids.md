# 0662: Export a list as CSV and page a list from ids

- Status: accepted
- Date: 2026-11-10
- Amends: 0637

## Context

ADR 0637 left the list export route and the id-RPC source of `defineListQuery` as not done. Apps wrote
their own CSV loops over `list.run`, each with its own quoting and none with a formula guard, and
wrote their own "load these ids in order" code around search results.

## Decision

Two functions ship in a new subpath, `better-supabase/list/export`, so the list entry keeps its size for apps that never export. Both work on a page callback, so they need no change to
`defineListQuery` and no new dependency.

- **`exportListCsv`** reads a cursor list page by page through `page(after, size)` and streams the
  file. The first page is read before the response starts, so a failed read is an error response with
  the error's status. Cells are quoted by RFC 4180 and a text cell that a spreadsheet would run as a
  formula gets a leading `'`. `maxRows` (default 100,000) ends the file; `pageSize` is 1 to 1,000.
- **`pageFromIds`** builds a cursor page from a page of ids and an id function. Rows follow the order
  of the ids and a missing or hidden row is dropped, so a page can be shorter than its ids.

## Not done

Relation filters, date buckets and free multi-sort in `defineListQuery`. Each changes the parsed query
type, the URL and nuqs parsers, the OpenAPI and JSON Schema output and the filter-tree builder, and
needs its own decision. Date buckets also need grouping by a truncated date, which PostgREST aggregates
cannot do without an RPC.

## Consequences

An export that outlives its request holds a connection per page read, one page at a time. A file that
reaches `maxRows` ends without a marker, so a caller who needs to know compares the row count with the
list's total.

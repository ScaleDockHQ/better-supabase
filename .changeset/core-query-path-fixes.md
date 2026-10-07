---
"better-supabase": patch
---

Fixes in the repository query path:

- `error` handlers get a frozen copy of the `DbError`, so a handler can no longer change the error the caller gets back.
- Arguments the builder rejects (a negative `limit`, an unknown operator) fail with the `table` and fire the `error` event, like every other error. Failed `db.$rpc()` calls fire the `error` event too, and the scores read of `db.$search({ score: true })` uses the connection's `timeout` and `retry` and reports its errors.
- `findMany` with a long `in` list no longer fails on a table whose primary key is text: the primary key order it adds on its own is re-applied by code point after the list is split. An `orderBy` you pass on text is still refused. Split reads that sort by an `int8` column compare exact values past 2^53.
- Cursor pages read the sort columns they add with their cast and codec, so an `int8` key keeps its exact value in `nextCursor`.
- Cursors from `paginate()` record the table and the sort they continue. Passing one with another `orderBy` fails with `invalid_request` instead of returning the wrong page. Cursors made before this release, and arrays from `encodeCursor()`, fail with `Invalid cursor`; start again with `after: null`.
- `toHttp()` writes `bigint` values as decimal strings instead of throwing, and TanStack Query keys from `createQueries()` hold `bigint` arguments as `{ $bigint: "<digits>" }`, so hashing them no longer throws.
- An array `contains`, `containedBy` or `overlaps` value with a brace in an element works inside an `OR`: PostgREST's logic tree parser read the brace as the end of the array.
- `exists()` on a table without a primary key selects one column instead of every column.

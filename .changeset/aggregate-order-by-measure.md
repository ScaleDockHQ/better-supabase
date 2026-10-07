---
"better-supabase": minor
---

`aggregate()` can sort groups by an aggregate. `orderBy` takes `{ _count: "desc" }` and measures such as `{ _sum: { amount: "desc" } }`, `_avg`, `_min` and `_max`, mixed with `groupBy` columns in a list: `orderBy: [{ _count: "desc" }, { status: "asc" }]`. The new `AggregateOrderBy` type describes the argument.

PostgREST can sort by `_count` only, which better-supabase sends as `order=count`; it returns an `invalid_request` error for a measure, and for `_count` on a table with a column named `count`. Over `better-supabase/postgres` and SQLite every sort compiles to SQL.

List facet counts use it: each facet keeps the `facetLimit` values that match the most rows, with ties in column order, instead of the first values in column order.

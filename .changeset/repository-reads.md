---
"better-supabase": minor
---

Repositories read with more filters and sorts, split long `in` lists instead of failing, and count pages cheaply by default.

- `findOnly({ where })` returns the one matching row, `null` for none and `multiple_rows` (409) for more.
- `where` takes json `path` filters (`JsonPathOps`), `match` and `imatch` regular expressions, and json containment with arrays. Reads longer than `urlLengthLimit` (6000) split along their longest `in` list.
- `orderBy` sorts by a to-one relation's column, `aggregate()` sorts groups by `_count` or a measure (`AggregateOrderBy`), and `paginate({ offset, limit })` returns an offset window. `defineReadSet` takes `auth.uid`.
- **Breaking:** list queries count with `count: "planned"` by default; pass `count: "exact"` for the old behaviour.
- **Breaking:** cursors record the table and sort, so cursors made before 0.6 and arrays from `encodeCursor()` fail with `Invalid cursor`. Start again with `after: null`.

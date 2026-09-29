---
'better-supabase': minor
---

Row caps and deterministic order.

- `defineSupabase(schema, { maxRows })` (default 1000, PostgREST's hosted `db-max-rows`). An unbounded read that returns `maxRows` rows sets `truncated: true` on the `query` event and logs a warning once per table; the result is unchanged.
- **Behaviour change:** `findMany` without `orderBy` now orders by the primary key, so repeated reads return rows in the same order. Views and keyless tables are unchanged.
- `gen` marks tables Postgres estimates at 10,000 rows or more with `large: true` in `supabase/snapshot.json`.
- New lint rule `unbounded-read` with `largeTables(snapshot)`: flags `findMany` without `limit` on large tables, or on every table with `strict: true`.

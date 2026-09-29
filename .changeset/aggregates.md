---
'better-supabase': minor
---

Aggregates in one request. `include: { _sum | _avg | _min | _max: { relation: { column: true } } }`
aggregates related rows next to each parent row, and `db.x.aggregate({ where, groupBy, _count, _sum,
... })` returns totals or one row per group, over PostgREST and SQL, typed in the configured casing.
`aggregate` is a spec and query-options method. PGRST123 (aggregates off) maps to `invalid_request`
with a hint, doctor BS210 warns when the app uses aggregates while `pgrst.db_aggregates_enabled` is
off (new `doctor.sources` option), and `SPEC_PINS.postgrestAggregates` pins the syntax.

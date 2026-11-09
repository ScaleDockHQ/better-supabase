# 0425: Count defaults to the estimated mode

- Status: accepted
- Date: 2026-11-08
- Amends: 0402

## Context

`repository.count()`, `page({ withCount: true })`, the keyset total and the
server resource list counted exactly, so each page of a large table scanned every
matching row. On the scale fixture an exact count over 200,000 visible customers
took 12 ms and the capped form 1 ms; the exact cost grows with the table.

## Decision

Without a mode, `count()` is `estimated`, `withCount: true` is `estimated`, the
keyset total is `estimated` and the resource list page counts `estimated`. An
estimated count is exact up to the PostgREST threshold (1,000 rows) and the
planner's estimate above it. `count: "exact"` and `count({ mode: "exact" })`
stay available. Internal existence checks stay exact. This is a breaking
default: code that compares a large count for equality passes `mode: "exact"`.

## Deferred

Returning `{ count, capped }` and a `formatPageTotal` helper need the executor
to report whether the planner answered; that is not in this change. The
scale test `supabase/tests/scale/scale_count_modes.test.sql` also did not finish
a 1,000,000-row seed within six minutes on the shared machine, so the numbers
above are from 200,000 rows.

## Consequences

`better-supabase upgrade` rewrites nothing and no data migration is needed.
Callers that need an exact total add `count: "exact"`.

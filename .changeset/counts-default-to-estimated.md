---
"better-supabase": minor
---

Breaking default: `count()`, `page({ withCount: true })`, the keyset total and the server resource list count in the `estimated` mode. The total is exact up to 1,000 rows and the planner's estimate above it, so a page of a large table no longer scans every matching row (an exact count over 200,000 rows took 12 ms, the capped form 1 ms). Pass `count: "exact"` or `count({ mode: "exact" })` where an exact total matters.

`better-supabase upgrade` rewrites no module and no data migration is needed. Returning `{ count, capped }` is not part of this change.

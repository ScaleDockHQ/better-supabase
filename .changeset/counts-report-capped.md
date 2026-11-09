---
"better-supabase": minor
---

Counts say whether the planner answered. `page.capped` is true when an offset page's `total` is the planner's estimate, `repository.counted()` returns `{ count, capped }`, and `formatPageTotal(page)` prints `12,300` or `~12,300` (pass `capped: (n) => ...` for another wording). `count()` still returns a number.

`better-supabase upgrade` rewrites no module and no data migration is needed.

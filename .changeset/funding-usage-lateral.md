---
"better-supabase": patch
---

`funding_award_usage` reads the deliveries of each period once. A scalar subquery in the select list was copied into every use of `s.used` when the planner flattened the query, so the deliveries policy ran three times per period. On the example's award the call went from 478 ms and 23,361 buffers to 145 ms and 16,627 buffers.

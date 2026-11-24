---
"better-supabase": patch
---

`gen` no longer plans a page index whose columns lead a longer index on the same table, so a facet that equals the front of a sort index adds no extra write cost.

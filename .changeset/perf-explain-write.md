---
"better-supabase": minor
---

`better-supabase doctor --explain-write <tables>` plans an insert (a copy of one row with fresh keys) and an update on each table in a rolled-back transaction, and reports the time of every trigger from the `EXPLAIN` plan.

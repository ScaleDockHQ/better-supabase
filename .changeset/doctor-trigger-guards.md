---
"better-supabase": minor
---

Doctor BS213 no longer reports a column that a row-level `before` trigger protects, once the trigger's comment names it with `better-supabase:guards(column, ...)`. Snapshots now record the marker and whether each trigger is disabled.

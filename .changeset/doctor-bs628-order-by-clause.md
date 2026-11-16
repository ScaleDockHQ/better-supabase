---
"better-supabase": patch
---

Doctor BS628 now reads only the ORDER BY clause of a list function, so a column selected after an inner `order by` and an `order by ... limit 1` that picks one row no longer report a missing cursor index.

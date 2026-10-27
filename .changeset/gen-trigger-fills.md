---
"better-supabase": patch
---

`gen` counts a row-level `before insert` trigger as filling a column a CHECK makes not null only when its PL/pgSQL body assigns that column (`new.col := …`, `new.col = …` or `select … into new.col`). A trigger that only validates no longer makes the column optional on insert. Snapshots record the assigned columns as `fills` on the trigger.

---
"better-supabase": minor
---

A numbering entity needs less config: `column` defaults to `number` when `table` is set, and an entity that names only `column` numbers the table of the subject with the same name. The tenant column already comes from the subject. A `column` without a table or a matching subject fails with an error that names both fixes.

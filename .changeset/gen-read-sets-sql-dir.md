---
"better-supabase": patch
---

`better-supabase gen` writes the read-sets module again when `sql.dir` points outside the project, as in a monorepo whose apps share one Supabase stack. It failed with "is outside the project root" while `gen --check` passed.

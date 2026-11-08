---
"better-supabase": minor
---

`better-supabase codemod config` removes the `columns` entries the render refuses: a `null` for an optional column the view a block runs over lacks anyway, and a `tenant` that repeats `sql.tenantColumn`. Doctor BS379 reports those entries as errors and names the codemod.

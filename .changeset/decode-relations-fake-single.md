---
"better-supabase": minor
---

`db.$decode(table)` decodes relations embedded in a raw row (`select=*,tag(*)`) at every depth, with a codec failure reported as `invalid_value`. `createFakeClient` answers `.single()` over no data like PostgREST: `PGRST116` with the row count in `details`, also for `.maybeSingle()` over several rows. Doctor reports a hand-merged `settings` JSON blob as BS620.

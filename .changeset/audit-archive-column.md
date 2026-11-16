---
"better-supabase": minor
---

`audit()` takes `archive_column` and `archive_value`, so an update that sets or clears a soft-delete or status column is recorded as `<entity>.archived` or `<entity>.restored` instead of `<entity>.updated`. Block tables with an `archivedAt` column pass it on their row audit trigger. The audit module moves to version 14; run `better-supabase upgrade`.

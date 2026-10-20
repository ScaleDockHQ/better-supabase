---
"better-supabase": minor
---

Add `migrationBetween(code, base, next)` to `better-supabase/create`. It returns the migration that takes a deployed design to the next one for added tables and columns, and refuses breaking or unsupported changes with the changes that caused it.

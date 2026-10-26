---
"better-supabase": minor
---

`better-supabase/create` adds `gatePlan` and `parseRenameHints`, which decide renames and block destructive actions in a migration plan shaped like pg-delta's (ADR 0106). The `db diff` wiring follows.

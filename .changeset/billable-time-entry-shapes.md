---
"better-supabase": patch
---

Billable time works with time tracking's per-type record columns (`blocks.time-tracking.on.<type>.column`) and duration entries (`endedAt` mapped to `null`): it reads an entry's record from its column, computes the end from the start and `seconds`, leaves running timers out, and locks the duration and running mark of a billed entry.

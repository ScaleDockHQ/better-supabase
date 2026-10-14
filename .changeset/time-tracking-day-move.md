---
"better-supabase": patch
---

Moving a time entry to another day now rolls up both days. `time_entry.updated` carries `previousStartedAt`, a metric's `time` function may return several times, and `metricsSink` rolls up one window per day they fall on.

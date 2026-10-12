---
"better-supabase": minor
---

`watch` and `useWatch` from `better-supabase/powersync` take `refresh: { everyMs, onReconnect }`, so a read that runs on the executor's server `fallback` reruns without waiting for a local change: on an interval (skipped while PowerSync reports it is offline) and when PowerSync connects again. `PowerSyncDatabaseLike` gains the optional `currentStatus` and `registerListener` members that `refresh` reads.

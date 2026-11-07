---
"better-supabase": minor
---

`useBlockQuery` and `useBlockMutation` from `better-supabase/next/client/offline` pause while `useOffline()` is true: a read keeps its last data and reports `offline: true` instead of an error and runs once on reconnect, and a write queues once and runs on reconnect. The block controllers gain `setOffline(offline)`, an `offline` option and an optional `offline` state field.

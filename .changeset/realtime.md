---
"better-supabase": minor
---

Realtime topics support presence, write their own policies and build triggers from parent rows.

- `defineTopic` takes `presence`, and subscriptions get `track`, `untrack`, `members()` and `onPresence`.
- `realtime.policies: { from, output }` writes every topic's `realtime.messages` policies on `sql sync`, with a `--check` drift test.
- `topic.triggerSql()` takes lookups through parent rows, an `event` name and a custom `payload` (`TriggerLookup`).
- `realtime.users` gives live queries on a table a per-user topic, and `useBroadcast` works with a plain supabase-js `client`.

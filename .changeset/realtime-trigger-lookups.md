---
"better-supabase": minor
---

`topic.triggerSql()` fills placeholders from parent rows and sends custom events. A value in `values` can be a lookup `{ from, via, select, key? }` that reads a column of another table's row, through the changed row's column or another lookup, so a topic keyed by a thread or a tenant on a parent row needs no hand-written trigger. The new `event` option names the broadcast event, for every operation or per operation, and `payload` sends an object of columns, lookups and `{ sql }` expressions with `realtime.send` instead of the row change. The trigger now skips a row whose topic is null. `TriggerLookup` and `TriggerValue` are exported from `better-supabase/realtime`.

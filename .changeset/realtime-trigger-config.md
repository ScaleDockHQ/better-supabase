---
"better-supabase": minor
---

`realtime.triggers` entries take everything `topic.trigger()` does: lookups through a parent row (`{ from, via, select, key }`), a payload object whose values are columns, lookups or `{ sql }` expressions, one event name per operation, extra `topics` with their own values, and `functionSchema`. `sql sync` passes each entry to the topic's `trigger()`, so the config and the call write the same SQL. `topic.trigger()` without `betterSupabase` takes lookups by database names too, with `key` defaulting to `id`, and `realtime-tables` is required only for triggers that call `better_supabase.broadcast_topic()`.

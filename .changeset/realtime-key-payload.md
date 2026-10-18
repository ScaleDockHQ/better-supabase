---
"better-supabase": minor
---

Topic triggers stop sending whole rows. This changes behaviour: the default message is now `{ operation, schema, table, id, values }`, the primary key and the topic values, so subscribers refetch the row through the Data API and their column grants apply. Before, every subscriber of the topic received every column.

- `topic.trigger(table, options)` is the one trigger API. Pass `betterSupabase` for typed table keys and parent-row lookups, `payload` for a custom object or `"row"` to keep whole rows on purpose, and `topics` to send the same change to more topics.
- `triggerSql(betterSupabase, table, options)` is deprecated and calls `trigger(table, { ...options, betterSupabase })`. Its default payload changes too.
- `rowKeys` reads the new message on the client. `rowChange` reads the `payload: "row"` shape.
- `realtime.triggers` entries take `payload: "keys" | "row"`, and the config loader now accepts `realtime.triggers` at all.
- `better_supabase.broadcast_topic()` sends the key payload, takes a fourth `'row'` argument, accepts `{name=column}` placeholders, and refuses to run as a `before` trigger. A topic value with characters topics don't allow raises a warning and skips that send instead of failing the write; generated trigger functions do the same per topic.
- Doctor BS337 warns about trigger functions that broadcast whole rows without the `payload: "row"` marker, such as 0.8 `triggerSql` functions. Snapshots record trigger arguments, and the source and comment of broadcasting trigger functions.

Run `better-supabase sql sync` and create a migration to update `broadcast_topic()`. See [Realtime triggers](https://bettersupabase.com/docs/migration/0.8-to-0.9#realtime-triggers).

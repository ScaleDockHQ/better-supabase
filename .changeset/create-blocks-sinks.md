---
"better-supabase": minor
---

`createBlocks` returns `sinks`: a `searchSink` over the search block, so trashed, purged and restored subjects update the index, and a `metricsSink` over the metrics block for the events in the metrics block's `sink` option. Pass them to `outbox.relayRoute({ consumers: { ...app.sinks } })`.

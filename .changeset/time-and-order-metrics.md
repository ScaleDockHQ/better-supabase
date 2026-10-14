---
"better-supabase": minor
---

Time tracking and orders ship metric definitions. Time entries get a generated `seconds` column and carry `startedAt` in their events; `timeTrackingMetrics()` sums tracked seconds per start day, and `timeEntryMetricTime` buckets entry events by that day. `orderMetrics({ currency })` defines orders placed, revenue and average order value, with `ORDER_METRIC_EVENTS` for the sink. `metricsSink` takes a `time` option and `createBlocks` a `metricTime` option for events whose rows sit at another time.

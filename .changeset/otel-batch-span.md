---
"better-supabase": minor
---

`otel()` records a `BATCH` span for the round trip when an executor runs the reads of one `db.$many` call together, as the direct Postgres executor does. The span carries `db.operation.batch.size` and is marked failed when any read fails. Plugins that wrap `executor.batch` now see these batches too.

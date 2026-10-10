---
"better-supabase": patch
---

The data exporter's `sink()` and `job` no longer fail for an export they can't claim, such as one cancelled, deleted or already finished before its `data_export.requested` event arrived. The sink threw `DATA_EXPORT_NOT_FOUND`, so the outbox relay retried the batch until it dead-lettered it and held every later event for that consumer behind it. The sink now skips that event and the job completes; a failing export still throws and retries. `exporter.run()` keeps returning the `not_found` error.

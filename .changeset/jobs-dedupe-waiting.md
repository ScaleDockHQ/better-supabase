---
"better-supabase": minor
---

Jobs can coalesce only onto waiting jobs. `enqueue(queue, payload, { dedupeKey, dedupe: "waiting" })`, or `enqueue_job(..., dedupe_running => false)` in SQL, returns the id of a job with the same key that no worker has claimed yet, and otherwise queues a new one behind a running job, so a debounce trigger no longer drops a change made during a run. The default (`"always"`) keeps coalescing onto waiting and running jobs. On the table backend the unique dedupe index now covers waiting jobs only (`job_messages_waiting_dedupe_idx`), and `QueueBackend.send` takes the mode as an optional sixth argument.

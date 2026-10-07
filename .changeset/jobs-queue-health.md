---
"better-supabase": minor
---

Jobs report queue health for admin pages. `jobs.stats(queues?)` returns per queue the `ready`, `inFlight`, `delayed` and `dead` counts and `oldestAgeSeconds`; `jobs.listDead(queue, { limit, before })` pages through dead letters with their payload, context, attempts and last error; and `jobs.retryDead(queue, { ids, limit })` enqueues them again. The `jobs` module adds `job_queue_stats`, `list_dead_jobs` and `retry_dead_jobs` on both backends. `QueueBackend` gains the optional `stats`, `listDead` and `retryDead`, and `testQueueBackend` checks them when a backend has them.

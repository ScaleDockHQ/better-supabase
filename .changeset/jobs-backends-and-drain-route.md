---
"better-supabase": minor
---

Jobs run without pgmq or pg_cron when you want. `kits.jobs.options.backend: "table"` stores jobs in `better_supabase.job_messages` and claims them with `for update skip locked`, and `kits.jobs.options.scheduler: "drain"` stores schedules with a time zone each. `jobs.drainRoute({ secret, handlers })` is a route for Vercel Cron that enqueues due schedules and drains queues within a time budget, and `drain` takes a `budgetMs`. `schedule` takes `{ timeZone }` and validates the cron expression first. `createJobs` accepts any `QueueBackend` (API version 1), with `sqlQueueBackend`, `pgmqPublicBackend` and the `testQueueBackend` conformance kit. The `jobs` module is now version 2: `better-supabase sql upgrade` drops the old four-argument `schedule_job`.

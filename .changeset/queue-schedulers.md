---
"better-supabase": minor
---

`createQueue` takes a `scheduler` apart from the queue, so Supabase Queues or Vercel Queues pair with Supabase Cron or Vercel Schedules. The new `ScheduleProvider` interface (`apiVersion: 1`) is what decides when a schedule fires; every `QueueProvider` is one, and without `scheduler` the queue's own schedule methods run as before.

- `sqlScheduler(sql, { mode })` and `transportScheduler(transport, { mode })` are Supabase Cron (`mode: "pg_cron"`, the default) or the drain scheduler (`mode: "drain"`) apart from the queue. A pair that can't deliver, such as pg_cron with Vercel Queues, throws a `TypeError`.
- `vercelScheduler(Schedules, { bridge, jitter, namespace })` writes each schedule to Vercel Schedules (pass `Schedules` from `@vercel/schedules`). A tenant becomes a namespace. On Vercel Queues a run publishes to the job's topic and `vercelQueueRoute` unwraps it; on a Supabase queue it publishes to the `bridge` topic, where `vercelScheduleBridgeRoute(jobs, { client })` checks the probe and enqueues the run once per `executionId`.
- `jobs.schedulesRoute({ secret })` runs `runSchedules` for a clock on a queue without a drain, and `jobs.enqueueScheduledRun(input)` enqueues one run another scheduler fired. `runSchedules` sends due runs with `sendBatch` when the queue has it, which `vercelQueueProvider` now does.
- `blocks.queue.options.httpTick` installs `better_supabase.http_tick()` and a pg_cron job that calls the drain or schedules route every minute with the URL and token in the Vault secrets `jobs_tick_url` and `jobs_tick_token`, so Supabase Cron can be the clock.
- `drainRoute` and `schedulesRoute` accept `caller: "vercel-schedule"`, which lets a Vercel schedule run in without the secret. Use it only on a private function with a `schedule/v1beta` trigger.
- `vercelScheduleConfig(options)` returns the `functions` and `schedules` fragments of `vercel.json`, and `vercelCronOf`, `vercelScheduleNameOf`, `vercelNamespaceOf`, `parseVercelScheduleRun` and `isVercelScheduleMessage` convert to and from Vercel's formats.
- A job delivered from a schedule run exposes `job.schedule` with its `name`, `executionId` and `scheduledAt`. `jobs.unschedule(name, { tenant })` takes the tenant a scheduler keeps apart.
- `testScheduleProvider` from `better-supabase/testing` checks a scheduler.

The `jobs` SQL module moves to version 14 (`schedule_has_work` becomes a client function, plus `http_tick` with `httpTick`). Run `better-supabase upgrade` and apply the new migration.

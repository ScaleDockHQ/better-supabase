---
"better-supabase": minor
---

`jobs.ensureSchedules(definitions, { prefix, tenant })` keeps a named set of schedules in step: it writes each definition, removes the schedules under the prefix (and tenant) that the set no longer names, and returns `{ scheduled, removed }`. Every name must start with the prefix, and every payload and cron is checked before anything is written. Under the drain scheduler, `schedule_job` now keeps a schedule's next run when it is written again with the same cron and time zone, so re-scheduling no longer skips a run that is due but not yet drained.

---
"better-supabase": minor
---

The jobs drain makes fewer database calls. `ensureSchedules` writes only the schedules that are new or whose cron, time zone, queue, tenant or payload changed, so a reconcile on every drain costs one `list_schedules` call when nothing changed. `drainRoute` asks once which queues have a job to claim and claims only from those, instead of one `claim_jobs` call per empty queue. The `queue` SQL module moves to version 11: it adds `ready_job_queues(queues text[])` and a `payload` column on `list_schedules`, and `QueueProvider` gains an optional `readyQueues`. Run `better-supabase upgrade`; until then the drain reports the missing function and claims from every queue as before.

---
"better-supabase": minor
---

Under the drain scheduler, `better_supabase.schedule_job` called from SQL without `next_run` stores the schedule without a next run, and the next drain computes its first run in the schedule's time zone, counted from when it was written, so a database trigger can schedule a job directly. Before, such a schedule ran on the next drain whatever its cron. `schedule_job` also rejects a schedule that isn't five cron fields, a macro or an interval. The `jobs` module moves to version 5: `job_schedules.next_run` is nullable, a `first_after` column is added, and `claim_due_schedules` returns `first_after` (`better-supabase sql upgrade` drops the old function).

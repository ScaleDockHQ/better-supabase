---
"better-supabase": minor
---

One dispatcher runs the recurring cleanups. The new `housekeeping` SQL module adds
`better_supabase.maintenance()`, which runs each due job and records the outcome, the
`maintenance_jobs` view, and `maintenance_schedule()`, which registers the dispatcher with
pg_cron when it is installed. The `approvals`, `trash`, `webhook-inbox`, `rate-limit`,
`idempotency` and `chat-sdk-state` modules contribute their purge and expiry functions as jobs,
and keep the function names. Run `better-supabase upgrade` to install the module.

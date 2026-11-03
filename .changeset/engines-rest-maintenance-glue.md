---
"better-supabase": minor
---

Maintenance can run without pg_cron: `maintenanceTimer` and `maintenanceTick` in `better-supabase/blocks/queue` run `better_supabase.maintenance()` from the `block_ticks` queue, and skip the run when pg_cron already has it. `support` (expired sessions), `usage` (idempotency keys and computed meters) and `webhooks-out` (the delivery log) now register their cleanups with the `housekeeping` module, which becomes a requirement of those three modules. `leave` refuses a request that starts in a `leave_year` period the periods block locked or closed, with the hint `LEAVE_PERIOD_CLOSED`. `finance.reconcile` matches an account's unmatched bank transactions to their best open invoice. `doctor` reports BS510 when the housekeeping module is installed and nothing schedules `maintenance()`.

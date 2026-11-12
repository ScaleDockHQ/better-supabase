---
"better-supabase": minor
---

A queue schedule can name a `probe`, a SQL function without arguments that returns whether there is work. A due schedule whose probe returns `false` stays due and enqueues nothing, so every-minute schedules stop enqueueing a job on each idle drain tick. The outbox, webhooks-out and webhook-inbox modules add `outbox_has_work()`, `webhook_deliveries_has_work()` and `webhook_inbox_has_work()` to use as probes. `listSchedules` returns each schedule's probe, and `ensureSchedules` rewrites a schedule whose probe changed. The queue module goes to version 12.

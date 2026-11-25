---
"better-supabase": minor
---

`support.openTicket` and the new `tasks.createWithSla` run as one database call. The create function makes the task and starts its SLA clocks in one transaction, so a failed clock start no longer leaves an open ticket behind. The TypeScript hooks of `tasks.create` and `sla.start` no longer fire inside `openTicket`; the composite's own hook does.

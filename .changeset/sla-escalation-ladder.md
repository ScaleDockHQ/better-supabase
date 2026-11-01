---
"better-supabase": minor
---

SLA policies take an escalation ladder. `savePolicy` accepts `escalations`, a list of steps with `at` (the share of the clock's time), `action` (`notify`, `reassign` or `page`) and a `target` for `reassign`. `check()` fires each step once per clock, records it in `sla_escalations` and emits `sla.escalated`. A type's `on` binding takes an `owner` column that `reassign` writes.

Run `better-supabase upgrade` and generate a migration: it adds `sla_policies.escalations` and the `sla_escalations` table.

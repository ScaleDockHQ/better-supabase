---
"better-supabase": minor
---

The `sla` and `targets` SQL modules and their blocks add service levels and goals. A service-level policy per record type and priority sets first response, next response and resolution minutes, optionally in business hours with a time zone. Binding a record type's status and priority columns starts, pauses, resumes and resolves its clocks, `record(subject, "responded")` meets a response clock, and `check()` records `sla.warned` and `sla.breached` and notifies the record's watchers. A target is a goal per period for a member, a team or the organization. Its progress is computed for won deal amounts and counts, completed work items and paid invoices, or read from a value the app keeps.

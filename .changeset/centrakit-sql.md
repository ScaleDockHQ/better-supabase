---
"better-supabase": patch
---

The audit trigger reads `import_run()` once per statement for the actor kind (a scalar subselect
that Postgres evaluates once), instead of once per audited row. `blocks.audit.options.exempt` is
typed as `readonly (string | { table, reason })[]`; a bare glob string still works, and doctor
reports it (BS315).

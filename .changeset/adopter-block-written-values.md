---
"better-supabase": minor
---

Doctor reports BS361 when an app table's check constraint or enum rejects a
value the installed block writes. The check renders the block with the
adopter's config and reads the literals its insert and update statements write,
so a value the config stops the block from writing, or one only an API caller
can pass, is not reported. A narrower check, such as one on an adopted
`notification_deliveries.status` that predates digests, still reports the
`held` and `digested` writes and names the constraint.

The notifications docs name the statuses the block writes (`pending`, `sent`,
`failed`, `skipped`, `held` and `digested`) and the migration guide from 0.48 to
0.49 explains the upgrade.

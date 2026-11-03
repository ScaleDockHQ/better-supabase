---
"better-supabase": minor
---

Doctor reports BS361 when an app table's check constraint or enum rejects a
value a block writes. The check reads the values the installed module declares
in its own `check (column in (...))` constraint and compares them with the
catalog check or enum on the column the block writes, including the values
mapped through `blocks.<name>.values`. A narrower check, such as one on an
adopted `notification_deliveries.status` that predates digests, makes the
block's inserts fail.

The notifications docs name the statuses the block writes (`pending`, `sent`,
`failed`, `skipped`, `held` and `digested`) and the migration guide from 0.48 to
0.49 explains the upgrade.

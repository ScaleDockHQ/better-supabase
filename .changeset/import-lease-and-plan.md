---
"better-supabase": minor
---

`start_import_run` stores `options.plan` (expected rows per entity) and takes a 30 second lease. `heartbeat_import_run` extends the lease. `finish_import_run` sets `outcome` to `completed`, `completed_with_issues` or `incomplete` when an entity is below its plan. `get_import_run` returns the plan, outcome and lease.

`better-supabase upgrade` rewrites the imports module. The next schema migration adds the columns and `heartbeat_import_run`. No data migration is needed.

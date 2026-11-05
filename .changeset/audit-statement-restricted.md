---
"better-supabase": minor
---

`audit(..., statement => true)` works when the app keeps restricted details in their own table
(`options.restricted`, or a mapped `audit_log_restricted_details`). The statement trigger writes the
log rows and the restricted rows from the transition tables in one insert each, instead of raising
"needs an audit log without the restricted table", and `import_run()` and the tenant name are read
once per statement. On in-process Postgres (PGlite), an `update` of 48 rows went from a median of
20.3 ms in row mode to 8.5 ms in statement mode, and an `update` of 5,000 rows from 937 ms to
504 ms. The audit module is version 11: run `better-supabase upgrade`, then `add --adopt`.

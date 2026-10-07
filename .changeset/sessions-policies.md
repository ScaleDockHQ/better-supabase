---
"better-supabase": minor
---

`sql.modules.sessions.options.policies` makes `sql sync` write a restrictive `bs_session_active` policy on every table the schema files and migrations create in `schemas`, so revoked sessions lose access everywhere without a policy per table by hand; `options.exclude` skips tables by `schema.table` glob. Doctor's new BS320 warns about RLS tables without a restrictive `session_active()` policy while the `sessions` module is in `sql.modules`. `declaredTables` from `better-supabase/sql` lists the tables a set of SQL files creates.

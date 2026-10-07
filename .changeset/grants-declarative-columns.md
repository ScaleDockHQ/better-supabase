---
"better-supabase": minor
---

`sql.modules.grants.options.fromPolicies` and `sql.modules.sessions.options.policies` read your declarative schema files instead of every migration, and follow `drop table` and `drop policy` statements, so a table or policy that an old migration created and a later change removed no longer comes back under pg-delta. Projects without declarative schema files still read their migrations. `expose` also takes column privileges such as `"update(title, body)"` or `"select(id, title)"` (for `select`, `insert` and `update`), which the `grants` module writes as column grants; the config schema accepts them and doctor BS106 leaves them out of its table-level check.

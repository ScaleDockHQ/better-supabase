---
"better-supabase": minor
---

The `grants` module now writes the complete privilege set of every table and function in `expose`: it revokes everything from `public`, `anon`, `authenticated` and `service_role`, then grants what the entry lists. `service_role` gets every table privilege unless the entry sets `serviceRole`. Functions are keyed by their signature (`"search_notes(text, integer)": { execute: ["authenticated"] }`) and get `execute` for the listed roles and `service_role`. `sql.modules.grants.options.fromPolicies` derives grants for tables `expose` doesn't list from the permissive policies in the schema files and migrations; `policyGrants` from `better-supabase/sql` does the same parsing.

Breaking: a table in `expose` loses privileges it doesn't list, including `truncate`, `references` and `trigger`, on the next sync.

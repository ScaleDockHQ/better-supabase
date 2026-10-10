---
"better-supabase": minor
---

With `sql.modules.grants.options.fromPolicies`, a table the schema files create that has no permissive policy and no `expose` entry is now service-only: `sql sync` revokes `public`, `anon` and `authenticated` on it and grants `service_role` every privilege. BS106 no longer asks for a `select` grant on those tables. New doctor check BS115 reports such tables that still hold grants on the live database, and BS116 reports `security definer` functions in an exposed schema that `anon` or `authenticated` can execute while no `expose` entry or policy uses them.

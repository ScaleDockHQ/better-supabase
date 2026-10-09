---
"better-supabase": minor
---

SQL modules can be called over the Data API without exposing their schema, and land their extensions and event triggers in migrations. Run `better-supabase sql sync` and create a migration for the new function bodies.

- `sql.modules.<module>.api` writes `security invoker` entry points for the functions apps call into a schema, and `rpcTransport(supabase, { schema: "api" })` calls them there. Doctor BS312 points at the option.
- `sql add`, `sync` and `upgrade` write the modules' extensions into a `<stamp>_better_supabase_extensions.sql` migration, and data files repeat extensions and event triggers so pg-delta plans need no hand edits (doctor BS321, BS323).
- The `ensure-rls` module enables row level security on every new table outside the Supabase-managed schemas.
- A write that breaks a `jsonb-schemas` schema fails with a `validation` error whose `issues` name the column.
- `sql.modules.sessions.options.policies` writes a restrictive `bs_session_active` policy on every table, and doctor BS320 reports tables without one.
- The `grants` module keys functions by signature, takes column privileges such as `"update(title, body)"`, and derives grants from permissive policies with `options.fromPolicies`.
- Policies check tenant permissions once per statement, module functions pass `supabase db lint`, and module actions follow a renamed sibling key.
- **Breaking:** `grants` writes the complete privilege set of each entry in `expose`, so a table loses privileges it doesn't list, including `truncate`, `references` and `trigger`, on the next sync.

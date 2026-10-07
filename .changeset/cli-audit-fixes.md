---
"better-supabase": patch
---

Fix several CLI introspection, `gen` and `doctor` bugs.

- Introspection reads constraints, indexes, policies, triggers and grants of table partitions, so doctor no longer reports BS106 for every partition and `gen` keeps their CHECK unions and unique keys.
- Grants to `public` appear in the snapshot as `PUBLIC`, for tables and columns. BS106 accepts access through `grant ... to public` and catches it on a `serviceRole` table, and BS213 counts it.
- Invalid indexes, left by a failed `create index concurrently`, are left out.
- The catalog fingerprint includes role memberships, so a `grant role to role` invalidates the cached snapshot.
- `gen`, `introspect`, `seed`, `skills` and `sql` ignore line endings when they compare files, so a checkout with `core.autocrlf` passes `--check` and isn't rewritten on every run.
- `gen --watch` imports the read-set and topic policy modules again with the project files they import, so a run sees the `generated.ts` the previous run wrote.
- `gen` closes the database connection when `supabase/config.toml` can't be read, instead of waiting for the pool to time out.
- A computed view column is no longer typed as insertable.
- Function argument and return types resolve in the type's own schema, so a function that takes an enum from another schema gets that enum's values.
- Doctor points a policy finding at the policy on the right table when several tables have a policy with the same name. The report's `object` carries the policy's `table`.
- Typegen and the argument-order query run in parallel.

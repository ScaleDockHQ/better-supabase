---
"better-supabase": patch
---

Fixes in `better-supabase/create/lite`:

- `verifyQuery` reports a policy `to public` with the role `public`. It tested the joined `pg_roles` row, which role 0 doesn't have, so the policy applied to no role and the matrix marked it `denied`.
- `accessMatrixTests` tries a select as `select 1 from <table>`. The `count(*)` query always returned one row, so a select that row level security denies failed as `rows:1`.
- `verifyFiles` returns the files Postgres rejects as `sql_error` issues and the modules PGlite skips in `skipped`, as `validateDesign` does. Before, a rejected file dropped its tables from the catalog without an issue.

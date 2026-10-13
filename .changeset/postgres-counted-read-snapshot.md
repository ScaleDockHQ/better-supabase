---
"better-supabase": patch
---

The direct Postgres executor runs a counted read's rows and count queries in one transaction, so both see the same snapshot. On `createPostgres()` clients this also halves the round trips of `findMany({ count: "exact" })`.

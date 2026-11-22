---
"better-supabase": minor
---

`db diff` stops under pg-delta when the schema files create an object pg-delta cannot manage, lists the objects in `data.blocking` and writes nothing. Pass `--no-strict-coverage` to leave them out as before. The Supabase CLI path now passes `--strict-coverage` to `supabase db schema declarative sync`. `db diff --prove` applies the plan to a clone of the local stack and refuses a plan that does not converge, loses rows or rewrites a table without saying so.

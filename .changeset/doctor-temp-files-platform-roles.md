---
"better-supabase": patch
---

Doctor BS208 no longer warns when the only statements that spilled to temporary files ran as Supabase's service roles, such as PostgREST's schema cache query on a large schema. With `pg_stat_statements` installed, the top statements it lists are the app's own.

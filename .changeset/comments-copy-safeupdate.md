---
"better-supabase": patch
---

`comments.copy()` works over `rpcTransport`. `copy_comments` cleared its scratch table with a `delete` without a `where` clause, which pg-safeupdate refuses in the PostgREST sessions Supabase runs, so the copy failed with `DELETE requires a WHERE clause`. A test now checks that every `delete` in the SQL modules has a `where` clause.

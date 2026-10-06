---
"better-supabase": patch
---

`gen` and `introspect` keep each function's arguments in declaration order. Extension functions with unnamed arguments (pgvector, citext) no longer change their argument order in `database.types.ts` and snapshots after a database reset.

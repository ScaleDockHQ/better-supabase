---
"better-supabase": patch
---

Bind `json` and `jsonb` arguments of `rpc()` correctly over direct Postgres when `database.types.ts` is absent: argument types now come from the catalog, so string arguments are JSON-encoded like they are with generated types.

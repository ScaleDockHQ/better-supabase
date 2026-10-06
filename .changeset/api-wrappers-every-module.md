---
"better-supabase": patch
---

`sql.modules.<module>.api` now writes entry points for the functions of `jobs`, `idempotency`, `webhook-inbox` and `access` too. Those modules granted their functions in a loop, which the wrapper generator didn't see; they now grant each function in its own statement, and a registry test keeps every module from granting in a loop.

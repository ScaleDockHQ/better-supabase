---
"better-supabase": minor
---

`db.$rpc` works over the Postgres executor. `postgresExecutor` had no `rpc()`, so a request running over a direct connection (an API key or a job) failed with `Executor "postgres" does not support rpc()`. It now calls `schema.name(arg => $1, ...)` with the named arguments and returns what PostgREST returns: an array for a set-returning function, one value or row otherwise, and `null` for `void`, with the same error mapping and `invalid_request` for a missing function. `RpcContext` gains an optional `function` with the generated metadata, which `$rpc` passes to every executor.

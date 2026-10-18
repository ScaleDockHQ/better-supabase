---
"better-supabase": minor
---

`db.$rpc` now casts result columns that have a codec to `text`, as repository reads do, over both PostgREST and the Postgres executor. An `int8` above 2^53 in a `returns table` or `returns setof` result now reaches its `bigint` codec intact, and a `numeric` keeps its digits. `{ raw: true }` calls send no column list. Executors receive the list as `RpcContext.select`; an executor that ignores it returns the full row, as before.

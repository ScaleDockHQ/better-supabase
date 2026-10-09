---
"better-supabase": minor
---

`db.$rpc` is typed per overload, accepts `null` arguments and runs over the Postgres executor. Run `better-supabase gen`, then `better-supabase codemod 0.6`, which lists every `$rpc` call to review.

- `gen` keeps every overload of a function as a union in `Functions`, and `$rpc` picks the overload by the argument names the call passes. Arguments are typed `T | null`.
- `postgresExecutor` implements `rpc()`, so requests over a direct connection (an API key, a job) call functions too.
- `rpcTransport` and the jobs block's `pgmq_public` backend accept a typed `SupabaseClient<Database>` without a cast.
- **Breaking:** `gen` types function results as nullable: scalars, `setof` scalar elements, a single row and each `returns table` column are `| null`. Set `functions.<name>.notNull` in `better-supabase.config.ts` to `true` or to the columns that are never null.
- **Breaking:** `$rpc` returns rows of a table and `returns table` records in the configured casing with the configured codecs, like repository reads, typed as the model row. Delete hand-written key mapping around those results, or pass `{ raw: true }` for what PostgREST sent.

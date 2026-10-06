---
"better-supabase": minor
---

**Breaking for code that calls functions:** `gen` types function results as nullable. A scalar result, each element of a `setof` scalar, a single table row and each `returns table` column are `| null`, since Postgres can't promise a value: a `strict` function returns `null` for a `null` argument, a SQL function returns `null` when its query finds no row, and an aggregate over no rows is `null`. Rows of `returns setof` a table, `void` and `Json` results are unchanged. When a result is never null, set `functions.<name>.notNull` in `better-supabase.config.ts` to `true` for the whole result or to the `returns table` columns that are never null; `gen` fails on a name it can't find. To upgrade, run `better-supabase gen`, then handle `null` where the type checker reports it or add `notNull` for the functions you know; `better-supabase codemod 0.6` lists every `$rpc` call.

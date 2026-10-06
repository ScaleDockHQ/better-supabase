---
"better-supabase": minor
---

PostgREST reads whose query string is longer than `maxUrlLength` (6000 characters by default) are split along their longest top-level `in` list into reads that fit, run in parallel and merged, instead of failing with `414 URI Too Long`. This covers reads without `limit`, `offset`, `count` or a single row; an `orderBy` on selected number, uuid, date or time columns is applied again after the merge. Other oversized reads return `invalid_request` with a hint before any request is sent. Set the limit with `defineSupabase(schema, { maxUrlLength })` or `postgrestExecutor(client, { maxUrlLength })`; `PostgrestExecutorOptions` types the option.

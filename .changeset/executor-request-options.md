---
"better-supabase": minor
---

`updateMany` and `deleteMany` take `maxAffected`. A write whose `where` matches more rows fails with the new `max_affected` error kind (400, with `maxAffected` in the error and its Problem Details) and changes nothing. Over PostgREST it sends `Prefer: handling=strict, max-affected=N`, which needs PostgREST 13; set `defineSupabase(schema, { postgrestVersion: "12.2" })` on an older server and such a call fails with `invalid_request` before any request. The Postgres and PowerSync executors check the count inside the statement or transaction and roll the write back, and `testExecutor` checks that custom executors do the same. The rules plugin's `strict()` preset adds `requireMaxAffected` (default maximum 1000, writes by primary key exempt), and `better-supabase/lint` has a matching opt-in `require-max-affected` rule.

Every read, write and `$rpc` call takes `timeout` (milliseconds, combined with `signal`, failing with `timeout` instead of `aborted`) and `retry` (supabase-js retries for `GET` and `HEAD`). Set both for a connection with `connect(client, context, { timeout, retry })` or on `postgrestExecutor(client, { timeout, retry })`.

`createMany` and `upsertMany` take `defaultToNull: true` to write `null` for columns a row leaves out, and mutations take `count: "planned"` or `"estimated"`. The `maxUrlLength` option is renamed to `urlLengthLimit` (the old name still works), and when unset the limit is the lower of 6000 and the client's own `urlLengthLimit`. `betterSupabase.executorOptions()` returns the `postgrestExecutor` options a definition implies.

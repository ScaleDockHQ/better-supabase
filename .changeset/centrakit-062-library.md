---
"better-supabase": minor
---

Search joins and watch lookups compare keys on their own type, and a watch update fires only when `key` or `watch.columns` changed. Doctor BS632 reports a pair whose live types differ.

An unbounded `list` that PostgREST cuts at `maxRows` returns a `truncated` error after a probe finds another row. `truncation: "warn"` keeps the previous warning. Set `maxRows` to the project's `[api] max_rows`.

`usage_overview` reads every meter in one statement. `usage.remaining()` calls `usage_remaining` and does not load the meter catalog.

The server schema loads each table module on first use and function metadata on the first `rpc` call. `gen.serverTables: "eager"` imports every table up front.

Statement-level audit triggers skip an import that audits one summary per entity.

`finish_import_run` treats a run as completed with issues only when a `conflicted` count is above zero.

`better-supabase/client/lite` is an Auth and Realtime client. Install `@supabase/auth-js` and `@supabase/realtime-js` to use it. Cookie sessions stay on `better-supabase/client`.

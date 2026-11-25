---
"better-supabase": minor
---

Request stats now count services that call `betterSupabase.connect()` themselves:
`connect(supabase, { claims })`, `connect({ executor: postgresExecutor(sql), storage })`
and the client `contextFromSession()` returns find the current request's
recorder, so one page's `calls` matches `pg_stat_statements`. Stats gain
`decodes` (session cookie parses) next to `verifications`, and `phases` with
calls per phase. `bsb.phase(name, run)` marks a wrapper's calls as
`authorization`, `write` or any phase, and the `bsb.action` log line ends with
the phase counts and `decodes`. `bsb.debugRoute()` answers 404 with a JSON
`reason` when debug is off or `?id=` is missing.

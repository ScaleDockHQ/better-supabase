---
'better-supabase': minor
---

Request budget. `db.$stats()` and `ctx.stats()` report calls, sequential
waves, tables and time. `createNext(sb, { debug: { budget } })` gives every
render a request id in the proxy, records every `next.server()` scope into
it, warns in development when a render goes over budget, adds
`x-bs-db-calls` to route handler responses and serves totals from
`next.debugRoute()`. `expectDbBudget(page, ...)` in `better-supabase/testing`
fails a Playwright test when a page gets chattier.

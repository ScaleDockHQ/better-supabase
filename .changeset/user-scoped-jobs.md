---
"better-supabase": minor
---

Jobs run as the user who enqueued them. `bs.forContext(job.context)` returns repositories over direct Postgres as the context's user, with its tenant as `tenant_id` and the `better_supabase.tenant` setting, so RLS applies inside the handler. It fails with `forbidden` when the context has no user and never falls back to the service role; an impersonating admin stays in `act`. The new `claimsFor(userId, context)` server option rebuilds claims a custom access token hook would add, at the time the job runs. The jobs, webhook inbox, actor and MCP docs now use `forContext` or `actingAs` instead of `admin.$with(job.context)`, which still bypasses RLS, and a new guide covers jobs, webhooks and agents without a session.

---
"better-supabase": minor
---

`entryContext(bsb, entry)` from `better-supabase/server` builds the same `ServerContext` from a request, a resolution, an auth state or a cron call. `cronHandler(bsb, { name, secret }, run)` is a guarded `GET` and `POST` route for a scheduler that runs `run(ctx, request)` as the service role.

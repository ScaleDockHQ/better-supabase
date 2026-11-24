---
"better-supabase": minor
---

`shareGuard(ctx, db)` from `better-supabase/server` lets an app's own service run inside a `share: "tenant"` fill. It gates a db the app builds itself, for example over its own Postgres pool, so it reads only the entry's tables and functions, and a refused read keeps the entry from being stored. The db must run as the caller: its claims carry the caller's `sub` and role, so a db for another user, for the service role or for no one is refused. Outside a shared fill it returns the db unchanged. `inTenantFill(ctx, tables, body)` from `better-supabase/testing` runs a service the way a shared fill does.

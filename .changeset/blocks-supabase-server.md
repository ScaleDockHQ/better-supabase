---
"better-supabase": minor
---

Blocks run on `@supabase/server`'s Postgres clients: `ctx.postgres` and `ctx.postgresAdmin` work wherever a block takes a SQL client (`sqlTransport`, `createJobs`, `createInbox`, `createIdempotency`, `createOutbox`, `purgeAuditLog`, `entitlementMembers`), so an app keeps one pool and one connection string. `withBlock(key, create)` from `better-supabase/server` is a middleware entry that puts a block service on the context, after `withBetterSupabase` and `withPostgresAdminClient` and under every framework bridge. The blocks overview documents which connection each block needs and the runtimes a SQL connection runs on.

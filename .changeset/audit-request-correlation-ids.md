---
"better-supabase": patch
---

Audit entries record the request and correlation ids of the action that made them, so an app can group an event with the row changes of the same request. `createServer` gives every context a request id (the incoming `x-request-id` when valid, else a new UUID) and a correlation id (the incoming `x-correlation-id`, else the request id), exposes them as `ctx.requestId` and `ctx.correlationId`, sends them as headers on `ctx.db` requests and sets them as the transaction-local `better_supabase.request_id` and `better_supabase.correlation_id` settings for `ctx.sql`. The `requestIds` server option renames the headers, ignores the incoming ones or turns the ids off, and `ContextOptions` takes `requestId` and `correlationId` for jobs.

The audit module (version 6) reads the ids from those settings, then from the request headers (`requestIdHeader` and `correlationIdHeader` options), keeps only ids of 1 to 128 safe characters through `better_supabase.request_id_or_null`, and indexes `correlation_id` on a managed log. The ids are metadata and never grant access. Run `better-supabase sql sync` and generate a migration to pick up the module change.

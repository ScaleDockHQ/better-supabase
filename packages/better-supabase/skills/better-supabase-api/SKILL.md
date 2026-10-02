---
name: better-supabase-api
description: Build HTTP APIs, Edge Functions and MCP servers on Supabase with better-supabase adapters. Use when adding a route, REST resource, oRPC procedure, Edge Function, MCP tool, webhook, background job or idempotent endpoint.
---

# APIs with better-supabase

Every adapter resolves the caller once and hands you `{ auth, db, supabase }`.
`auth.kind` is `user`, `anon`, `service` or `invalid`.

## Workflow: add an endpoint

1. Pick the adapter for the runtime (table below). Setup code for each is in
   [references/adapters.md](references/adapters.md).
2. Decide who may call it with `allow` (see below).
3. Use `db` from the handler context and return its `Result`, a plain value
   or a `Response`.
4. For a table exposed as REST, prefer `bs.resource(...)` over hand-written
   routes, and regenerate `openapi.json` with `better-supabase openapi emit`.
5. Add an API test that calls the endpoint as a user and as another tenant
   (the `better-supabase-testing` skill).

Done when the endpoint rejects callers outside `allow`, errors come back as
Problem Details (no hand-built error JSON), and `openapi emit --check` passes
if the project has an OpenAPI file.

## Who gets in

`allow` defaults to `['user']`. Use `['user', 'anon']` for public endpoints
and `['service']` for machine callers. Rejected callers get a 401 with a
`WWW-Authenticate` header, or a 403, as Problem Details.

## Adapters

| Where          | Setup                                               | Handler                                                                                      |
| -------------- | --------------------------------------------------- | -------------------------------------------------------------------------------------------- |
| Next.js        | `createNext(sb)` in `lib/supabase.server.ts`        | `next.route((req, { db }) => ...)`, `next.action({ input: schema }, (input, { db }) => ...)` |
| Hono           | `createHono(sb)`, `.use('/api/*', bs.middleware())` | `c.var.db`; `bs.resource('customers', {...})` for REST                                       |
| oRPC           | `createOrpc(sb)`, `base.use(bs.middleware())`       | `bs.unwrap(context.db.customers.findMany(...))`                                              |
| Edge Functions | `createEdge(sb, { cors: true })`                    | `Deno.serve(bs.handler((req, { db }) => ...))`                                               |
| MCP            | `createMcp(sb, { name, version, resources })`       | `.tool({ name, input, run: (args, { db }) => ... })`                                         |

Don't build error JSON by hand; errors become Problem Details.

## REST resources

`defineResource` / `bs.resource(table, { operations, list, input })` gives you
list, get, create, update and delete, with validation and paging (`{ items, page }`).
`createOpenApi(sb, { resources })` describes the same routes, and
`better-supabase openapi emit --check` keeps `openapi.json` in sync.

## Background work (`better-supabase/jobs`, needs `sql add jobs idempotency webhook-inbox`)

- `createJobs(postgres.admin, { queue_name: zodSchema })` runs on Supabase Queues (pgmq): `enqueue` in the request, then `work` or `drain` in a worker. The handler throws to retry. `schedule(name, cron, queue, payload)` uses pg_cron. Queue names are lowercase letters, digits and underscores. With a service-role Supabase client instead of SQL, it uses the `pgmq_public` RPCs (no dedupe or schedules).
- `createIdempotency(postgres.admin).handle(request, handler)` for POST endpoints that clients retry.
- `createInbox(postgres.admin, { source, secrets }).receive(request)` for webhooks; `process(handler)` later.

Done when a failing job is retried and then archived after `maxAttempts`,
and a replayed webhook or POST doesn't run twice.

## Testing

Sign tokens with `signLocalJwt` or `asUser` from `better-supabase/testing`;
the adapter verifies them against the local JWKS. See the `better-supabase-testing` skill.

Docs: https://bettersupabase.com/docs/frameworks/hono.md (and `next`,
`orpc`, `edge`, `mcp` under `/docs/frameworks/`).

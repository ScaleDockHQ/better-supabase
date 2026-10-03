---
name: better-supabase-api
description: Build HTTP APIs, Edge Functions and MCP servers on Supabase with better-supabase adapters. Use when adding a route, REST resource, oRPC procedure, Edge Function, MCP tool, OAuth or agent scopes, webhook, background job, cleanup cron or idempotent endpoint.
---

# APIs with better-supabase

Every adapter resolves the caller once and hands you `{ auth, db, supabase }`.
`auth.kind` is `user`, `anon`, `service` or `invalid`. For sessions, claims
and the OAuth client or agent behind a token, see the `better-supabase-auth`
skill.

## Workflow: add an endpoint

1. Pick the adapter for the runtime (table below). Setup code for each is in
   [references/adapters.md](references/adapters.md).
2. Decide who may call it with `allow`, and which scopes a delegated token
   needs with `scopes` (see below).
3. Use `db` from the handler context and return its `Result`, a plain value
   or a `Response`.
4. For a table exposed as REST, prefer `bs.resource(...)` over hand-written
   routes, and regenerate `openapi.json` with `better-supabase openapi emit`.
5. Add an API test that calls the endpoint as a user and as another tenant,
   and with a delegated token that lacks the scope (the
   `better-supabase-testing` skill).

Done when the endpoint rejects callers outside `allow` and tokens without its
`scopes`, errors come back as Problem Details (no hand-built error JSON), and
`openapi emit --check` passes if the project has an OpenAPI file.

## Who gets in

`allow` defaults to `['user']`. Use `['user', 'anon']` for public endpoints
and `['service']` for machine callers. Rejected callers get a 401 with a
`WWW-Authenticate` header, or a 403, as Problem Details.

`scopes` limits what a delegated token may do: a token from the Supabase
OAuth server (`client_id` and `scope`) or one exchanged for an agent (an
RFC 8693 `act` chain). The guard options of `bs.route`, `bs.action`,
`bs.handler` (edge) and `bs.middleware` (Hono, oRPC) take it, next to
`allow`:

```ts
export const GET = bs.route(
  (request, { db }) => db.customers.findMany({ limit: 20 }),
  { scopes: ["customers:read"] },
);
```

With `.claims(schema)` on the definition, `auth.claims` is typed in every
adapter (`c.var.auth`, `context.auth`, the edge handler's `auth`, MCP's
`ctx.auth`). Read roles from it; don't parse the claims again.

A token without the scope gets a 403 with an `insufficient_scope`
challenge. The user's own session holds no `client_id` or `act`, so `scopes`
never limits it. RLS still decides the rows: the token's `sub` is the user.

## Adapters

| Where          | Setup                                                           | Handler                                                                                  |
| -------------- | --------------------------------------------------------------- | ---------------------------------------------------------------------------------------- |
| Next.js        | `createNext(betterSupabase)` in `lib/supabase/server.ts`        | `bs.route((req, { db }) => ...)`, `bs.action({ input: schema }, (input, { db }) => ...)` |
| Hono           | `createHono(betterSupabase)`, `.use('/api/*', bs.middleware())` | `c.var.db`; `bs.resource('customers', {...})` for REST                                   |
| oRPC           | `createOrpc(betterSupabase)`, `base.use(bs.middleware())`       | `bs.unwrap(context.db.customers.findMany(...))`                                          |
| Edge Functions | `createEdge(betterSupabase, { cors: true })`                    | `Deno.serve(bs.handler((req, { db }) => ...))`                                           |
| MCP            | `createMcp(betterSupabase, { name, version, resources })`       | `.tool({ name, input, run: (args, { db }) => ... })`                                     |

Don't build error JSON by hand; errors become Problem Details.

## REST resources

`defineResource` / `bs.resource(table, { operations, list, input })` gives you
list, get, create, update and delete, with validation and paging (`{ items, page }`).
`createOpenApi(betterSupabase, { resources })` describes the same routes, and
`better-supabase openapi emit --check` keeps `openapi.json` in sync.

Pass `pagination: "cursor"` to a resource, `defineListQuery` or an MCP table
for lists that clients read page by page: the list takes `after` instead of
`page`, returns `nextCursor` and `hasMore`, and `size` stays capped by
`maxPageSize`. The OpenAPI document and the JSON Schema describe the cursor.

## MCP servers

- Tools run as the calling user, so RLS applies to every call.
- `authorize(ctx, tool, args)` refuses a call (`{ allowed: false, reason, scopes }`; with `scopes` it is a 403 `insufficient_scope`). `visible(ctx, tool)` hides tools from `tools/list`. Put a permission or a label in a tool's `meta`; clients never see it.
- `scopes` on `createMcp` only advertises scopes. Refuse calls in `authorize`, reading `toSession(ctx.auth).delegation?.scopes`.
- Set `allowedOrigins` and `allowedHosts` (every host the server answers on, previews and local included) against DNS rebinding, and `resourceDocumentation` to a page that explains how to connect.

## Background work (`better-supabase/jobs`, needs `sql add jobs idempotency webhook-inbox`)

- `createJobs(postgres.admin, { queue_name: zodSchema })` runs on Supabase Queues (pgmq): `enqueue` in the request, then `work` or `drain` in a worker. The handler throws to retry. `schedule(name, cron, queue, payload, { timeZone })` uses pg_cron, or with `kits.jobs.options.scheduler: "drain"` a `jobs.drainRoute({ secret: process.env.CRON_SECRET, handlers })` route that Vercel Cron calls; `kits.jobs.options.backend: "table"` runs without pgmq. Queue names are lowercase letters, digits and underscores. With a service-role Supabase client instead of SQL, it uses the `pgmq_public` RPCs (no dedupe or schedules).
- `createIdempotency(postgres.admin).handle(request, handler)` for POST endpoints that clients retry.
- `createInbox(postgres.admin, { source, secrets }).receive(request)` for webhooks; `process(handler)` later.
- Times are `Temporal.Instant`: `EnqueueOptions.runAt`, `Job.enqueuedAt`, `Job.visibleUntil`, `InboxMessage.receivedAt` and webhook timestamps.
- Schedule cleanup with pg_cron at a quiet hour: `better_supabase.purge_job_archive('<queue>')`, `purge_webhooks()`, `purge_audit_log()` and `purge_idempotency_keys()`. Only `service_role` can execute them.

Done when a failing job is retried and then archived after `maxAttempts`,
a replayed webhook or POST doesn't run twice, and each kit table has a purge
schedule.

## Direct Postgres on the server

- `createPostgres()` opens a pool; `createPostgres({ pool })` runs on an existing `pg.Pool`. `asUser` and `anon` transactions get Supabase's role timeouts (8 s and 3 s); `statementTimeout` takes a number or `{ admin, authenticated, anon }`.
- `createMany` and `upsertMany` split inserts past 65,535 bind parameters into several statements in one transaction, so large batches don't need manual chunking.
- In serverless functions, connect through the transaction pooler (port 6543), not a direct connection.

## Testing

Sign tokens with `signLocalJwt` or `asUser` from `better-supabase/testing`;
the adapter verifies them against the local JWKS. See the `better-supabase-testing` skill.

Docs: https://bettersupabase.com/docs/frameworks/hono.md (and `next`,
`orpc`, `edge`, `mcp` under `/docs/frameworks/`),
https://bettersupabase.com/docs/kits/jobs.md and
https://bettersupabase.com/docs/auth/postgres.md.

# 0054: A Vercel Marketplace block and a Vercel Queues jobs backend

- Status: accepted
- Date: 2026-10-20
- Amended 2026-10-21: the Partner API, a sealed access token and usage per period.

## Context

An app that sells through the Vercel Marketplace has to keep installations,
resources, plans and invoices, verify Vercel's webhooks, exchange SSO codes and
report usage. Each such app wrote the same tables and calls. Jobs ran only on
Postgres queues, which an app already on Vercel Queues could not reuse.

## Decision

`better-supabase/blocks/vercel-marketplace` is a service-role block with the
`vercel-marketplace` module. It adds no `@vercel/*` dependency: webhook
signatures use WebCrypto HMAC-SHA1, the SSO `id_token` is verified with the
core JWS code against Vercel's JWKS, and API calls use `fetch` with a bearer
token the app supplies per installation. Invoices keep the state of the newest
event (`event_at`), and meter reports are stored before they are sent, so a
failed send is retried.

`vercelQueueBackend(client)` in `better-supabase/blocks/jobs` is a
`QueueBackend` (`apiVersion: 1`) over `@vercel/queue`. The client is passed in
and typed structurally, so the package is an optional peer with a tested range
(`>=0.8 <0.9`) and never loaded by the library. Vercel Queues has no dead
letters, stats or schedules, so those methods are absent or refuse and the
backend declares `leases: false`.

## Alternatives considered

Depending on `@vercel/integration-utils` tied the block to a package that moves
faster than the Marketplace API. Putting the backend in its own subpath added an
entry point for a few hundred bytes.

## Consequences

The Marketplace API shapes (billing, invoices, SSO) follow Vercel's documentation
and are covered by unit tests with a fake `fetch`, not by a live integration.
A new `@vercel/queue` minor needs a range bump and a conformance run.

## Amendment: the Partner API and usage per period

An app that sells through the Marketplace also serves the Partner API, and
each one rebuilt the routes, the OIDC check and the secret handling. The block
now serves them through `partnerApi(options)`, one `Request` to `Response`
handler. It verifies Vercel's OIDC token against
`https://marketplace.vercel.com/.well-known/jwks` (the path the discovery
document names), checks the issuer, the audience (the client id) and the
expiry, and requires the `installation_id` claim to match the path. The SSO
exchange uses the same check.

The installation's access token is sealed in Vault
(`access_token_secret_id`), so `accessToken` became optional. Tenants are kept
per installation and per resource with whether the integration created them,
so removing a resource or an installation can delete an empty tenant it made.
Secrets go to Vercel only; the block keeps the app's refs for them so a
rotation can revoke the old keys, and it calls `revoke` only after `rotate`
resolved and the new refs are stored.

`reportUsage` used to send one number as `dayValue`, `periodValue` and
`planValue` and stamp every pending row with the current period. It now sends
one request per billing period, with the total as `periodValue` and the total
minus `reported_quantity` as `dayValue`, and moves `reported_quantity` only
after a 2xx answer. `usageRoute` runs it from a cron caller.

The module is version 2. Its upgrade adds columns and functions and sets
`reported_quantity` to the quantity of every row already reported, so the
next report sends only what was added since.

## Amendment: push delivery

On Vercel, Queues pushes each message to a route by default; polling is the
exception. The backend only polled, so an app on push delivery wrote its own
callback, parsed the `{ payload, max_attempts }` body and skipped the schema
check. `vercelQueueRoute(jobs, options)` wraps the client's `handleCallback`
and runs each message through `jobs.runJob`, the schema check and tenant
context `drain` uses. The client's `retry` callback acknowledges the delivery
that reaches `maxAttempts`, and returns `afterSeconds` before that.

`receive` became optional on `VercelQueueClient`, so a `QueueClient` (which
only sends and handles callbacks) fits; `read` rejects without it. `send` sets
`retentionSeconds` for a delayed message, an hour past the delay and at most
the 7-day cap, since Vercel Queues refuses a delay longer than the retention.
The default consumer group stays `better-supabase`: a new group name would
move every polling app's cursor.

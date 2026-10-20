# 0054: A Vercel Marketplace block and a Vercel Queues jobs backend

- Status: accepted
- Date: 2026-10-20

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

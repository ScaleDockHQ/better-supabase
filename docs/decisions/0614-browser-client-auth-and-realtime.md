# 0614: A browser client with auth and realtime only

- Status: superseded by [0846](0846-keep-the-full-browser-client.md)
- Date: 2026-11-10
- Amends: 0560

## Context

ADR 0560 kept the full Supabase browser client. A later measurement put the
PostgREST, storage and functions clients at about 12 KB on routes that only
subscribe and read the session.

## Decision

`better-supabase/client/lite` builds an Auth client and a Realtime client from
`@supabase/auth-js` and `@supabase/realtime-js`. Both are optional peers.
Sessions persist in the storage the caller passes, or the Auth client's
default. Cookie sessions stay on `better-supabase/client`, which uses
`@supabase/ssr`.

## Alternatives considered

- A `realtime: false` option on supabase-js. Its constructor still builds
  `RealtimeClient`, and it does not drop PostgREST.
- Copying `@supabase/ssr`'s cookie storage into this package. Routes that need
  those cookies already import the full client.

## Consequences

A route that does not query Postgres from the browser can import the lite
client. The full client remains the default.

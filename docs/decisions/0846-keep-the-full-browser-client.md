# 0846: Keep the full browser client

- Status: accepted
- Date: 2026-11-13
- Supersedes: [0614](0614-browser-client-auth-and-realtime.md)

## Context

ADR 0614 added `better-supabase/client/lite`, which assembled an Auth client
and a Realtime client from `@supabase/auth-js` and `@supabase/realtime-js` to
save about 12 KB on routes that don't query Postgres from the browser. It
kept sessions in its own storage instead of `@supabase/ssr`'s cookies, so a
page on the lite client and a page on the full client didn't share a
session the same way, and every auth-js or realtime-js release had to be
checked against our assembly.

## Decision

The library builds browser clients only through `@supabase/ssr`'s
`createBrowserClient` (`better-supabase/client`) and never assembles a client
from Supabase's parts. `better-supabase/client/lite` is removed, and with it
the optional peers `@supabase/auth-js` and `@supabase/realtime-js`.

## Alternatives considered

- Keep the lite client next to the full one: two session stores to keep in
  step, for 12 KB on the routes that use it.
- Give the lite client `@supabase/ssr`'s cookie storage: that copies the
  part of `@supabase/ssr` that changes most often.

## Consequences

A route that used the lite client imports `better-supabase/client` and loads
about 12 KB more. Sessions follow `@supabase/ssr` everywhere in the browser.

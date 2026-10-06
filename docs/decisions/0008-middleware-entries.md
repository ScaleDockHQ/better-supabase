# 0008: Build the server and the adapters on @supabase/middleware entries

- Status: accepted
- Date: 2026-10-06

## Context

`@supabase/middleware` 1.0 defines how Supabase server code composes:
entries with one key each, prerequisites checked by the type checker, a
response seam for entries that edit the response, and composites that hide
internal keys. `@supabase/server` 1.9 deprecated its framework adapters
(`adapters/hono`, `/h3`, `/elysia`, `/nestjs`, removed on 2026-12-01) in
favor of per-framework bridges that run an entry array in the framework's
middleware slot.

better-supabase had its own request pipeline inside `createServer`, a leaf
`withBetterSupabase` entry that needed `withSupabase` before it, and one
hand-written adapter per framework, each repeating the guard, the cookie
application and the event flush. Edge CORS and the RFC 9728 metadata route
duplicated code `@supabase/middleware/cors` and
`@supabase/server/oauth-protected-resource` ship. An app could not put
`withPostgresClient` or `withCors` next to better-supabase without wiring the
context by hand.

## Decision

The request path is a pipeline of entries in `src/server/entries`:
`withSession` (the only cookie seam), `withTenant`, `withSupport`,
`withServerContext`, then the guard, the `withSupabase`-compatible keys
(`jwtClaims`, `userClaims`, `authMode`), `db`, `sql` and the replica pin
seam. `withBetterSupabase(server)` in `src/server/composite.ts` is the
composite of all of them, with `session`, `auth` and `guard` internal.
`server.context(request)` folds the first four once and runs them per call,
so the pipeline and the existing API share one implementation. Entries reach
the server's resolver and context builder through `serverCore(server)`, a
registry `createServer` and `extendServer` write.

The old leaf entry is renamed `withBetterDb`. Each framework gets a bridge in
`src/bridges`: `toHono`, `toEdge`, `toOrpc` and `toExpo` behind the existing
subpaths, and `toTanStackStart`, `toSvelteKit`, `toReactRouter`, `toH3` and
`toElysia` behind new ones. The new bridges are typed structurally, so they
add no peer dependency. `createHono`, `createEdge` and `createExpo`'s
handler run on the composite; edge CORS uses `withCors`, and the MCP metadata
document starts from `resourceMetadataResponse`.

## Alternatives considered

Keeping `withSupabase` as the first entry and adding better-supabase keys
after it would resolve the caller twice, and `withSupabase` reads no cookie
session, so browser routes would lose their caller. Wrapping the deprecated
`@supabase/server` adapters would have tied every bridge to code with a
removal date. Importing each framework's types would have added five
optional peers and their type checks to every install.

## Consequences

Any `@supabase/middleware` entry composes with better-supabase in any
framework that has a bridge, and the type checker reports wrong orders and
key collisions. A new framework needs a bridge of about ten lines plus a
`testAdapter` run, not a full adapter. The rename of the leaf entry is a
breaking change, recorded in its changeset. Edge preflights now need
`Access-Control-Request-Method`, which browsers always send. Revisit when
`@supabase/middleware` changes its entry contract (a new major) or ships
official bridges for these frameworks.

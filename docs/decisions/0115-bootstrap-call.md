# 0115: Read a page's user data in one bootstrap call, in a private or remote cache scope

- Status: accepted
- Date: 2026-10-28

## Context

A Next.js page under Cache Components streams its user data in islands, each a
`"use cache: private"` function. Each island built its own context, so a page
made one PostgREST call per island, plus a `session_active()` check and a read
of the authorization version when the app wanted them. The private cache is per
browser and isn't stored on the server, so every hard load paid for all of
them again. A cache shared across instances (`"use cache: remote"`) can't read
cookies, and the access token can't be part of its key because the token
rotates.

The core can't use dynamic SQL to batch the islands' reads, and an
`AuthorizationProvider` must not need a new `apiVersion` for it (invariant 10).

## Decision

The sessions module's `bootstrap` option maps names to app functions
(`bootstrap: { islands: "public.island_counts" }`). For each entry it renders
`better_supabase.bootstrap_<name>(args jsonb)`, `security invoker`, which
returns one jsonb: `session_active`, the token's `authz_version`, the `tenant`
from the arguments and the function's `data`. With `blocks.sessions.api` set,
the API schema gets a wrapper of the same name. The SQL is static, rendered
from the config, and the function runs as the caller, so its policies apply.

`bsb.bootstrap({ rpc, args, scope, tables, tags, redirect })` calls the
wrapper as the first statement of a cache function and returns plain data:
`{ session, tenant, authzVersion, sessionActive, data }`. React's `cache()`
runs it once per request and key, so ten islands share one RPC. It seeds the
authorization version cache (ADR 0096) with `authzVersion`. A false
`sessionActive` evicts the user's entries and, with `redirect`, sends the
caller there with `?reason=session_not_found`; without it the entry isn't
kept. `bsb.getAccess(boot)` returns the context, the tenant and `can()` bound
to that version, so islands stop rebuilding their context.

The scope is `"private"` (the default) or `"remote"`. Next.js forbids nesting
them, so each call picks one:

- Private entries ride in the App Shell. `stale` defaults to a 300-second
  floor that the token's lifetime no longer caps (`life.capToToken` restores
  the cap); development warns below 300 and below 30 seconds.
- Remote entries go through `bsb.remote(fn)`, which verifies the session
  outside the boundary and passes serializable key parts (`userId`,
  `sessionId`, `tenant`, `authzVersion`, the `share` value and the support
  session) as the first argument. The token travels through a handoff on
  `globalThis` (`next/remote-handoff.ts`) keyed by those parts, so only the
  verified caller's request fills it and a rotation keeps the entry. `share`
  is `"session"` by default, `"user"`, or `{ key }`, which the docs mark as
  the app's own authorization decision. Lifetimes default to `revalidate` 300
  and `expire` 3600, so a remote entry reruns `session_active()` at least
  every five minutes.

Both scopes tag entries with the session tags and the tables, so
`evictSession`, sign-out and `refreshSessionCache` drop them, and both call
the same inner loader. The proxy's `verifySession: "bootstrap"` skips the
Auth call on document loads and leaves the check to the wrapper. `bsb.bootstrap`
calls `NextOptions.bootstrapSchema`, which defaults to `better_supabase`; an
app that exposes only its API schema to PostgREST sets it to that schema.

## Alternatives considered

- Batching each island's query in one request: PostgREST has no batch endpoint,
  and a generic batch function would be dynamic SQL.
- A wrapper that discovers app functions at runtime: dynamic SQL and a wider
  grant than one wrapper per configured name.
- The access token in the remote key: every refresh would miss, and the key
  would hold a credential.
- Layering a remote scope inside a private one: Next.js 16.4 forbids nested
  cache scopes.

## Consequences

A page with ten islands makes one bootstrap RPC per load, and a remote entry
serves a second instance without the RPC. The Next.js example's islands page
and its Playwright tests check both. The app writes one SQL function per page
and lists it in the config. `bootstrapSchema` doesn't follow
`blocks.sessions.api` yet, so an app with an API schema sets both; revisit
when the option can read the config.

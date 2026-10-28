# 0117: Refresh sessions through `@supabase/ssr` on every request, with one Auth call per refresh token

- Status: accepted
- Date: 2026-10-28

## Context

Up to 0.34 the proxy refreshed with a hand-written POST (`auth/refresh.ts`) and
wrote cookies with its own codec. It refreshed only on document loads and
Server Actions: it told prefetches and client navigations apart through the
`rsc` and `next-router-*` headers, which Next.js 16.4 strips before `proxy.ts`
runs. Router prefetches and App Shell renders then ran with an expired token,
and the `onExpiredPrefetch` workaround only skipped `protect`.

Refresh tokens are single use, with a 10-second reuse window; any other reuse
revokes the session. Parallel requests that refresh the same token race.
`@supabase/ssr` 0.12 writes cookies in the format every Supabase client reads,
sends the cache headers with its writes, and dedupes them, but only within one
client, and the upstream advice is one server client per request.

## Decision

Every adapter's resolver (`auth/resolve.ts`) refreshes an expiring session
(inside `leeway`, 60 seconds by default) through `refreshCookieSession` in
`auth/ssr-client.ts`. It makes one `createServerClient` for the request, calls
`auth.refreshSession`, and returns the cookie writes and headers for the
adapter to copy onto whatever response it sends: a `NextResponse.next()`, a
redirect, a `protect` rewrite or an `after()` result. It runs on every
non-asset request, prefetches included, so the App Shell renders with a fresh
token.

The client's `global.fetch` is a coalescing fetch. It sends one
`grant_type=refresh_token` request per refresh token, however many requests
ask, and answers repeats of that token from the response for 10 seconds. The
slot lives on `globalThis[Symbol.for("better-supabase.refresh")]`, so the
proxy and route handlers in other module graphs share it. A rotated token
(`refresh_token_already_used`) is a `raced` outcome that keeps the cookie; an
outage fails fast, without auth-js retries, and keeps the old token while it
is valid. The refreshed token is verified with the shared key set (ADR 0116)
and seeded into the session memo (ADR 0095), so the render doesn't verify it
again. The proxy never calls `getClaims()`, which would fetch a second key
set.

`verifySession` runs on document loads, detected through
`sec-fetch-dest: document`, which Next.js doesn't strip: `true` asks Auth on
every document load and `"bootstrap"` leaves the check to the bootstrap
wrapper (ADR 0115). Sign-out clears the session at every configured cookie
scope with `@supabase/ssr`'s cookie writes. `refresh: "navigation"`,
`onExpiredPrefetch`, `shouldRefresh` and the cookie codec are removed, and
`codemod 0.35` rewrites the options and lists the removed APIs.

## Alternatives considered

- Keeping the hand-written POST: a second cookie format to maintain, and
  without the ssr client's cache headers.
- Refreshing on document loads only: prefetches and App Shell renders would
  keep the expired token, and the headers that told them apart are gone.
- A lock per refresh token across instances: it needs shared storage. Within
  one instance the coalescing fetch removes the race, and across instances
  Auth's reuse window absorbs it.
- Calling `getSession()` or `getClaims()` to trigger the refresh: the first
  reads an unverified session, and the second fetches its own key set.

## Consequences

Ten parallel requests with an expired token make one Auth call, and router
prefetches no longer sign the user out through reuse detection. The adapters
load auth-js in the refresh path, about 5.5 KB gzip each, and `./ssr` grows
from 23262 to 30867 B. `clearSessionCookies` is async. Revisit when
`@supabase/ssr` shares refreshes across clients itself.

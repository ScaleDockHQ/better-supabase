# 0847: Call Supabase through its own clients

- Status: accepted
- Date: 2026-11-13
- Relates to: [0846](0846-keep-the-full-browser-client.md)

## Context

The library talked to Supabase in several hand-written ways: it parsed and
wrote the session cookies itself (`readSession`, `writeSession`), the Next.js
sign-in flows posted to the Auth endpoints directly (`passwordGrant`) and kept
their own PKCE verifier cookie, `sessionStatus` and `asSignedInUser` built
Auth requests by hand, the flags-sdk transport built Data API requests, and
the notifications block assembled public Storage URLs. Each one copied a
contract that `@supabase/ssr`, auth-js, postgrest-js or storage-js already
owns, so a change in Supabase's cookie format, error shape or headers could
break it without a type error. A session written by our flows and one written
by `@supabase/ssr` were not guaranteed to read the same way.

## Decision

Supabase is called only through its own clients:

- Session cookies are read with the `@supabase/ssr` helpers (`ssrSession`
  uses `combineChunks` and its base64url decoder) and written only by a
  `createServerClient`.
- The Next.js sign-in flows call auth-js on a `createServerClient`, so the
  session and PKCE cookies are the ones `@supabase/ssr` writes.
- `sessionStatus` calls `auth.getUser`, `asSignedInUser` calls
  `auth.signInWithPassword`, the flags-sdk transport calls `rpc`, and public
  Storage URLs come from `getPublicUrl`.

Code stays hand-written only where no Supabase client offers the call, and it
says so in a comment: `hs256.ts` (`@supabase/server` rejects a token without
a `kid`), the SSO admin endpoint (auth-js has no SSO admin API), the
resumable upload endpoint (storage-js has no resumable upload) and
`storageImageUrl` (the image loader has only the source URL). Access tokens
are still verified locally by `verifyCredentials`, so a valid token costs no
Auth call (invariant 7).

## Alternatives considered

- Keep the hand-written calls and test them against each Supabase release:
  the tests find a break only after a release ships, and the cookie format
  is `@supabase/ssr`'s to change.
- Wrap the clients behind our own interface: the same copying, one layer
  further away.

## Consequences

Breaking changes for 0.67: `readSession` becomes `ssrSession`, `passwordGrant`
and `applyCookieWrites` are no longer exported, the PKCE error code is
auth-js's `pkce_code_verifier_not_found`, and the notifications `avatars`
option takes a function. The sign-in parity test
(`tests/next/sign-in-parity.test.ts`) reads the cookies the flows write
through `createServerClient`, `createBrowserClient` and `ssrSession`. The
`./postgres` and `./blocks/outbox` entries grow by about 3.7 KB and 2.1 KB
gzip. The Server Component render benchmark stays at 1 verification and 4
clients per render.

# 0095: Share one token verification across cache scopes through a session memo

- Status: accepted
- Date: 2026-10-23

## Context

A Next.js page under Cache Components streams many islands, each with its
own `'use cache: private'` reader. React `cache()` does not reach across
those scopes, so every island resolved the caller again: it read the
cookie, verified the JWT and built a context. The resolver remembered
verified tokens, but concurrent scopes still raced through the first
verification, and nothing gave an island a verified session it could hand
to another API without reading the request again. Other adapters had the
same shape: two loaders of one request verified twice.

## Decision

`createServer` owns a session memo (`sessionMemo` in
`src/auth/snapshot.ts`): a bounded LRU (1000 entries by default) keyed by
the SHA-256 of the access token, computed with WebCrypto so runtime entries
import no Node built-ins. It stores the in-flight promise, so concurrent
scopes share one verification. An entry lives until
`min(exp, now + ttlMs)`; a failed verification and a signed-out result are
never stored. The key comes only from the token, never from a user id or a
header, so one process serving many users can't mix them up.

A hit returns a `SessionSnapshot`: `accessToken`, `claims`, `sessionId`,
`userId`, `expiresAt`, `issuedAt` and `authzVersion`. Times are epoch
seconds, like `AuthSession.expiresAt`, because the snapshot's fields cross
`use cache` serialization; this is an exception to ADR 0005, which keeps
Temporal for public time values. Snapshots are branded through a module
`WeakSet`, and `contextFromSession(snapshot)` builds the stateless clients
from a branded snapshot with no cookie read, no network call and no second
verification. A copy gets the `invalid` context, so callers pass plain
values into cached functions, never the snapshot.

In Next.js, `bsb.getClaims()` awaits `cookies()`, reads the session cookie,
looks it up in the memo and only then reads the clock. `claims()` (the
serializable `AuthSession`), `context()`, `cached()` and `bootstrap()` build
on it. The proxy seeds the memo when it refreshed the token, and the sign-in
flows seed it after a sign-in, so the render that follows reads a verified
entry. `bsb.evictSession(userId)` evicts the user from the memo, from the
authorization version cache (ADR 0096) and from every cache entry tagged
with the user's session. SvelteKit, TanStack Start, React Router, Hono and
Expo expose the snapshot to loaders and handlers.

`bsb.bootstrap()` (ADR 0115) is the usual reader in a page: its first island
verifies the token through the memo, and the others share the result through
React's `cache()`. The memo sits on top of the resolver's verified-token memo
and the one process-wide JWKS (ADR 0116).

## Alternatives considered

- A module-level map: hidden global state, shared between servers and test
  cases, and unbounded. The memo belongs to the server instance instead.
- Keying on the user id or `session_id`: a forged or stale token for the same
  user would hit a verified entry. Only the token's hash proves the token
  was verified.
- Passing the snapshot into cached functions: it would serialize the token
  into a cache key and lose the brand. Plain values keep the token out of
  every cache entry.
- Temporal instants in the snapshot: they don't survive `use cache`
  serialization.

## Consequences

Ten islands of one request verify the token once, and a hard load with a
valid token makes no Auth call. The memo holds verified tokens in memory
for at most their lifetime, so a revoked session stays usable until it
expires, the same as the local JWT check it replaces (`endedSession` is
still the way to catch revocations on document loads). `sessions: false`
turns the memo off. Revisit if Next.js adds a request store that spans
private cache scopes.

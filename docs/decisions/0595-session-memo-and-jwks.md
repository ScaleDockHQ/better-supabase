# 0595: Session memo on globalThis and stale JWKS

- Status: accepted
- Date: 2026-11-09
- Amends: 0116, 0340
- Amended by: 0633

## Context

ADR 0116 keys the verified-token memo by the raw token. The code hashed the
token with SHA-256 on every lookup, which that ADR rejected. The proxy and the
render are separate module graphs (ADR 0340), so a memo created inside
`createServer` did not see a session the other graph had seeded. JWKS refresh
after `cacheSeconds` made the request wait on the issuer.

## Decision

`sessionMemo` keys by the raw token. `createServer` keeps the default memo on
`globalThis[Symbol.for("better-supabase.session-memo")]`, so the proxy's seed
is a hit in the render. A custom clock, bound, ttl or counter object still
gets a private memo. `sharedJwks` returns a cached key set immediately when it
is past `cacheSeconds` and refreshes in the background. An unknown `kid` still
waits, because the cached set cannot verify it.

## Alternatives considered

- Keeping the digest: every hit paid for `crypto.subtle.digest`.
- One memo per module graph: the render verified a token the proxy had just
  verified.
- Blocking on a stale JWKS: a request every five minutes waited on the issuer.

## Consequences

A cold process still fetches the key set once. A failed background refresh
keeps the previous keys. `clearProcessSessionMemo` drops the shared memo in
tests.

# 0116: Fetch one JWKS per process; keep the verified-token memos until a benchmark retires them

- Status: accepted
- Date: 2026-10-28

## Context

Before 0.35 the signing keys were cached in three places: the single URL slot
inside `@supabase/server`, a `jwksSource` per `accessTokenResolver`, and the
vercel-marketplace block. Next.js loads the proxy and the render in separate
module graphs, so even one of those caches fetched twice on a cold start. On
top sat three memos of verified tokens: the session memo (ADR 0095), a
256-entry memo in `auth/resolve.ts` and another in `auth/access-token.ts`.

`@supabase/server` 1.9 rejects a token without `alg` and `kid` and accepts
HS256 only when the key set holds a symmetric key with that `kid`, but
Supabase Lite still issues HS256 tokens without a `kid`. A token signed by
another project with the same key algorithm passed when no issuer was set.

## Decision

`core/jwks-cache.ts` keeps one registry per process on
`globalThis[Symbol.for("better-supabase.jwks")]`, keyed by URL (and by the
custom `fetch`, through a `WeakMap`, so a test's fake fetch gets its own
entry). `sharedJwks(url, refresh)` fetches on first use and again after 300
seconds, shares one in-flight fetch between concurrent callers, keeps the
known keys when a fetch fails, refetches for an unknown `kid` at most once per
30 seconds and reads at most 256 KiB. The resolver passes the keys to
`verifyCredentials` inline, so `@supabase/server` keeps no resolver of its
own, and `jwksSource` (the access-token resolver, vercel-marketplace) goes
through the same registry. Keys are fetched with `auth.fetch`.

Without `auth.issuer`, a token whose `iss` isn't `fromSupabaseUrl(url)` is
rejected as `INVALID_ISSUER`. HS256 stays only for a token without a `kid`
and an explicit `jwtSecret` (Supabase Lite); every other token goes through
`verifyCredentials`.

The memos stay. The session memo is the one a page relies on: keyed by the
token's SHA-256, holding the in-flight promise. The resolver's memo is keyed
by the verifier's configuration (key set, project URL, audience, issuer,
secret) and skips the signature check for a token verified before. Removing
it waits for a benchmark showing that a warm verification against the shared
key set costs little next to a memo hit; the before and after numbers go in
that commit.

## Alternatives considered

- auth-js `getClaims()` in the proxy: it keeps its own module-level JWKS, a
  second fetch beside ours (ADR 0117).
- One cache per module graph: the proxy and the render would each fetch on a
  cold start.
- Dropping HS256: Supabase Lite projects couldn't sign in.
- Removing the resolver memo without numbers: it is on the path of every
  island that doesn't go through the session memo.

## Consequences

A cold start fetches the key set once across the proxy, the render and every
verifier in the process. A key rotation is picked up within 30 seconds of the
first token with the new `kid`. A token from another project fails without an
`issuer` setting. The memo layering stays one level deeper than planned until
the benchmark lands.

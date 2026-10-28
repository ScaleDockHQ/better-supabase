# 0116: Fetch one JWKS per process; keep one verified-token memo; build clients with createContextClient and createAdminClient

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

There is one verified-token memo per server. `createServer` owns it (the
session memo of ADR 0095, a bounded LRU of 1000 entries) and passes it to
`resolveAuth` as `memo`. The resolver looks a bearer or cookie token up in it
before verifying, so the proxy, every context, `getClaims()` and
`bsb.snapshot()` share one verification per token. The 256-entry memos in
`auth/resolve.ts` (keyed by the verifier's configuration) and in
`auth/access-token.ts` are removed, with the `checkedFor` layer behind them;
`clearVerifiedTokens()` became `clearKeyCaches()`. Without a memo (a bare
`resolveAuth` call, or `sessions: false`) every call verifies.

The memo is keyed by the token itself, not its SHA-256. The stored value
already holds the token, so the key costs no memory, and an awaited
`crypto.subtle.digest` on every lookup made a hit five times slower under
load. Failures and tokens without `exp` are never stored, and a hit answers
with the caller's token source (`cookie` or `bearer`).

The benchmark gated this step (`tests/server/context.bench.ts`, medians of
seven alternating runs on the same machine):

| Path                               | Before          | After            |
| ---------------------------------- | --------------- | ---------------- |
| first verification of a bearer     | 116.6 us        | 116.1 us         |
| memo hit                           | 14.8 us         | 14.1 us          |
| warm verification without a memo   | none            | 108.5 us         |
| same request again                 | 0.2 us          | 0.2 us           |
| islands render, first and repeated | 1.5 ms, 0.13 ms | 1.49 ms, 0.12 ms |

A warm verification against the shared key set still costs about eight memo
hits, so one memo stays; the extra layers under it bought nothing.

The server's clients are built with `createContextClient` (the user and anon
clients) and `createAdminClient` (the secret-key client) from
`@supabase/server/core`, with the keys passed inline so neither reads process
env. The admin client is created on first use behind a lazy Proxy, in the
style of `withSupabaseAdminClient`, and shared. A user client also passes its
token to Realtime through `realtime.accessToken`, which ignores the
`Authorization` header. Repository queries keep the bare `PostgrestClient`
fast path. `server.supabaseFor(auth, headers?)` is renamed
`server.contextClient(auth, headers?)`, and the 0.35 codemod rewrites the calls.

## Alternatives considered

- auth-js `getClaims()` in the proxy: it keeps its own module-level JWKS, a
  second fetch beside ours (ADR 0117).
- One cache per module graph: the proxy and the render would each fetch on a
  cold start.
- Dropping HS256: Supabase Lite projects couldn't sign in.
- Removing every memo: a warm verification costs about eight memo hits, and
  each island and route handler would pay it.
- Keeping the resolver and access-token memos: they repeated the session
  memo's work with their own bounds and eviction, and `evictSession` didn't
  reach them.
- Keying by the token's SHA-256: an awaited digest per lookup, for no memory
  saving.

## Consequences

A cold start fetches the key set once across the proxy, the render and every
verifier in the process. A key rotation is picked up within 30 seconds of the
first token with the new `kid`. A token from another project fails without an
`issuer` setting. `evictSession` and `sessions.clear()` reach every verified
token, since there is only one memo. `sessions: false` now turns off token
reuse entirely, and an `accessTokenResolver` used without `createServer`
verifies on every request.

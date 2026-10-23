---
"better-supabase": minor
---

Sessions verify once per request across cache scopes, and the Next.js proxy and sign-in take fewer round trips.

- `createServer` keeps a session memo keyed by the token's hash. `server.snapshot(request)` returns a verified `SessionSnapshot`, and `server.contextFromSession(snapshot)` builds a context from it with no cookie read, no network call and no second verification. In Next.js, `bsb.getRequestSession()` returns the snapshot, so ten `'use cache: private'` islands verify the token once. `sessionCacheKey`, `sessionIdTag`, `sessionMemo` and `bsb.sessions.stats()` are new; `createNext(..., { sessions })` sizes the memo or turns it off. See the [island pattern](https://bettersupabase.com/docs/frameworks/next-islands) and ADR 0095.
- `contextFromSession` accepts only a snapshot the server made: a copy (a spread, `structuredClone`, a cached function's arguments) gets the `invalid` context. Pass plain values into cached functions.
- The proxy refreshes a token only within `refreshSkewSeconds` of its expiry (`auth.leeway`, else 60), stores a refreshed session in the memo, and treats `refresh_token_already_used` as `raced`: it keeps the cookies the other request set instead of signing the user out.
- `serverTiming: true` now reports `bsb-auth` for resolving the session and `bsb-parse`, `bsb-verify`, `bsb-refresh` and `bsb-ended` per phase. `bsb-verify` used to be the whole resolution; read `bsb-auth` for that number now.
- `isPrefetch` also recognizes `next-router-segment-prefetch`, `x-middleware-prefetch` and `x-moz: prefetch`. Expo's `bsb.middleware()` and API routes no longer refresh on a prefetch, like the other adapters.
- `bsb.signIn({ email, password, next })` signs in from a Server Action in one Auth call, writes the cookies, stores the session for the next render and returns a same-origin `redirectTo` (and `mfa`), so the form calls `router.replace` once. `safeRedirectPath` and `passwordGrant` are exported from `better-supabase/server`.
- `AuthSession` and `SessionSnapshot` gain `issuedAt` (from `iat`) and `authzVersion` (from an `authz_ver` claim, or `null`).
- `createServer(def, { versions })` takes an authorization library's version cache. Authorizers get `{ versions, memo }` as a runtime, `invalidateSession(userId)` evicts the user from it, and `subscribeAuthzVersions({ client, topic, event, userIdKey, versions })` evicts users when the database broadcasts a change on a private Realtime channel. See [the version cache](https://bettersupabase.com/docs/extending/authorization-providers#version-cache) and ADR 0096.
- SvelteKit, TanStack Start, React Router, Hono (`c.var.snapshot`) and Expo hand loaders and handlers the snapshot.

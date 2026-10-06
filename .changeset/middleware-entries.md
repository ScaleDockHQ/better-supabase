---
"better-supabase": minor
---

`withBetterSupabase(server, options)` from `better-supabase/server` is now one `@supabase/middleware` entry that resolves the caller (a bearer token first, the session cookie second), enforces `allow`, `aal` and `scopes` with Problem Details, and contributes `bs`, `db`, `sql`, `tenant`, `support`, `replica` and the keys `withSupabase` writes (`jwtClaims`, `userClaims`, `authMode`), so `withPostgresClient` and other entries written for `withSupabase` run after it. On the way out it adds refreshed session cookies, the `no-store` headers and `bs-primary-until`, and hands pending event sends to `waitUntil`. It takes a server or the definition, plus `refresh`, `cookies`, `encode` (`tokens-only` writes refreshed sessions without the user object) and `cookieScopes` (expires the session cookie at the domains or paths an earlier deploy used).

Breaking: the leaf entry that needed `withSupabase` before it is renamed from `withBetterSupabase(betterSupabase)` to `withBetterDb(betterSupabase)`. Replace `withBetterSupabase(betterSupabase)()` after `withSupabase` with `withBetterDb(betterSupabase)()`, or drop `withSupabase` and use the new `withBetterSupabase(server)`.

`server.context(request)` runs the same entries, so every adapter and the pipeline share one implementation. `withSession`, `withGuard`, `serverCore`, `jwtClaimsOf`, `userClaimsOf` and `authModeOf` are exported for custom compositions, and `ResolveAuthOptions.cookie.encode` sets the session encoding for the whole server.

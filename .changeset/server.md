---
"better-supabase": minor
---

`withBetterSupabase(server, options)` from `better-supabase/server` is one `@supabase/middleware` entry that resolves the caller and contributes the request's database handles, and the server gains session and account helpers. `better-supabase` depends on `@supabase/server` `^1.9.1`.

- The entry reads a bearer token, then the session cookie, enforces `allow`, `aal` and `scopes`, and contributes `bs`, `db`, `sql`, `tenant` and the keys `withSupabase` writes. `server.context(request)` runs the same entries once per request. `createServer(betterSupabase, { db: { timeout, retry, urlLengthLimit } })` tunes its requests.
- Session cookies support the `@supabase/ssr` 0.12 `tokens-only` encoding (`encode: "tokens-only"`, doctor BS412 for mismatches), and `cookieScopes` and `clearSessionAtScopes` expire cookies an earlier deploy set.
- `sessionStatus` and `clearSessionCookies` run the ended-session check in any proxy. `endSessions(sql, userId)` and `suspendAccount(admin, sql, userId, { suspended })` end sessions and ban a user, and `deleteAccount` is exported on its own and returns the database's error, such as `ORGANIZATION_OWNER_REQUIRED`, with the `sql` option.
- An early refresh that hits a network failure keeps the user until the token expires, and the `otel` plugin records `db.$rpc` calls as spans.
- **Breaking:** the leaf entry `withBetterSupabase(betterSupabase)` that ran after `withSupabase` is renamed `withBetterDb(betterSupabase)`. Replace it, or drop `withSupabase` and use the new `withBetterSupabase(server)`.

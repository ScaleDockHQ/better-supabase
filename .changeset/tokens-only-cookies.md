---
"better-supabase": minor
---

Session cookies support the `@supabase/ssr` 0.12 `tokens-only` encoding, which keeps the user object out of the cookie so it stays small. `writeSession(cookies, name, session, options, { encode: "tokens-only" })` writes the access and refresh tokens alone, `readSession` reads both shapes, and `sessionEncoding(session)` says which one a cookie has. In the browser, `createClient(betterSupabase, { cookies: { encode: "tokens-only" } })` passes the setting to `createBrowserClient`, and `auth.userStorage` sets where auth-js keeps the user object. The default stays `user-and-tokens`; new apps should use `tokens-only` on both sides.

`clearSessionAtScopes(cookies, name, scopes)` from `better-supabase/ssr` returns the `Max-Age=0` writes that `clearAuthCookiesAtScopes` issues, to remove the session cookie at the domains or paths an earlier deploy used.

The browser client's `auth.current()` now reads the user's id, email and role from the access token claims and falls back to `session.user` only for a field the token lacks, so it no longer throws when a `tokens-only` cookie left auth-js without a user object. Doctor's new BS412 info finding reports sources where the server and the browser client set different encodings.

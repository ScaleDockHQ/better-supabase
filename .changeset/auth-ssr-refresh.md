---
"better-supabase": minor
---

The proxy and every adapter's middleware refresh sessions through `createServerClient` from `@supabase/ssr`, on every request they match, prefetches included. Parallel requests with the same refresh token share one call to Auth. Run `better-supabase codemod 0.35` to rewrite the options and list the rest for review.

Breaking changes:

- `refresh: "navigation"` is gone. Refresh is `true` by default, or a function of the request. `verifySession: "navigation"` is now `verifySession: "document"`, and checks document loads only (`isDocumentLoad` from `better-supabase/server`).
- `onExpiredPrefetch` is removed from `bsb.proxy()`: a prefetch now refreshes, so it never reaches `protect` with an expired session.
- `shouldRefresh` is removed from `better-supabase/next` and `better-supabase/server`. `shouldCheckSession` stays in `better-supabase/next` only.
- `clearSessionCookies` returns a promise. Await it before returning the response.
- The cookie writers are removed from `better-supabase/ssr` and `better-supabase/server`: `writeSession`, `refreshSession`, `pruneSessionChunks`, `sessionEncoding`, `clearSessionAtScopes`, `AUTH_CACHE_HEADERS` and their types. `@supabase/ssr` writes the cookies and their cache headers; `readSession` and `parseCookies` stay.

Other changes:

- A token whose `iss` names another project is rejected with `INVALID_ISSUER`. Set `auth.issuer` to enforce an exact issuer, or `false` to skip the check.
- The JWKS is fetched with `auth.fetch` and cached once per process, so every module graph (proxy, render, route handlers) shares one copy.
- When Auth can't be reached, a refresh fails within `timeoutMs` without auth-js's retries and keeps the cookies as they are.
- A response that `after` returns in `bsb.proxy()` keeps the refreshed session cookies and cache headers.

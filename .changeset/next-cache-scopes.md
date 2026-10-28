---
"better-supabase": minor
---

Pages can read the session, the authorization version and their data in one database call, and keep it in the App Shell. Run `better-supabase codemod 0.35` to list the lines to review.

- `bsb.cached()` sets `stale` to 300 seconds, so private entries ride in the App Shell. The token's lifetime no longer caps it, since the proxy refreshes every request; `life: { capToToken: true }` brings the cap back. In development a `stale` below 300 seconds warns once.
- `bsb.remote(fn, { share, tenant })` and `bsb.cached({ scope: "remote", key })` read user-scoped data in `"use cache: remote"`. The key carries the user, Auth session, tenant and authorization version, never the token. Support sessions get no remote token. Remote entries default to `revalidate` 300 and `expire` 3600.
- `bsb.bootstrap({ rpc, args, tenant, redirect })` calls the `better_supabase.bootstrap_<rpc>` wrapper that `blocks.sessions.options.bootstrap` generates. It checks `session_active()`, returns the token's `authz_ver` and the app function's data, seeds the authorization version cache, and calls once per request for the same arguments. An ended session is not cached, its tags are evicted, and with `redirect` the caller goes to `?reason=session_not_found`.
- `bsb.bootstrap()` calls the wrappers where the sessions block puts them: `gen` records its API schema (`blocks.sessions.api`, then `sql.api`) or its own `schema` in the schema metadata, and `bootstrapSchema` or the call's `schema` still override it.
- `proxy({ verifySession: "bootstrap" })` skips the proxy's Auth call for apps whose pages check the session in `bsb.bootstrap()`.
- `bsb.getAccess(source?)` returns the caller's context, session, tenant, authorization version and `can(permission)` from the request, a `SessionSnapshot` or a bootstrap result.
- `createNext({ rootParams: { locale, brand, tenant } })` adds `bsb.locale()`, `bsb.brand()` and `bsb.tenant()`, and contexts fall back to the `tenant` root param.
- `postAuthPath(source, fallback)` reads a safe `?next=` path from a request, search params or page props.
- `AuthzVersionCache` gains an optional `seed(userId, version)`.
- Doctor BS608 warns when a remote cache scope runs outside Vercel without `cacheHandlers.remote`.

Breaking changes:

- `sessionStale` and `SessionStaleOptions` are removed from `better-supabase/next`. Call `bsb.cached()` in the scope instead of `cacheLife({ stale: sessionStale(session) })`.
- `life.min` and `life.max` are removed from `bsb.cached()`. Use `life.stale` and `capToToken`.
- `bsb.contextFromSession(session, { token })` is removed. Pass the `SessionSnapshot` from `bsb.getClaims()`; the context is built without verifying the token again.

---
"better-supabase": minor
---

`bs.proxy(request, { expiredPrefetch: "render" })` skips `protect` for a prefetch whose session token expired, so the prefetch renders signed out instead of caching a redirect to sign-in, and the navigation refreshes the session. The default, `"protect"`, keeps today's behavior, so apps that already return early for `{ kind: "anon", reason: "expired" }` in `protect` can drop that check once they set the option.

`bs.context({ tenant })`, `bs.cached({ tenant })` and `bs.action({ tenant: (input) => ... })` scope a Server Component, a private cache or an action to a tenant from route params or input, instead of the `tenant` resolver, which has no request URL under `createNext`. The tenant goes where the resolver's result goes and gets the same checks. Pass it into your `'use cache: private'` function as an argument so it is part of the cache key. The new `ScopeOptions` type describes the option.

Under `createNext`, an async `tenant` resolver that found no tenant made `bs.context()` throw a `TypeError` in Server Components; it now gives a context without a tenant.

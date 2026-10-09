---
"better-supabase": minor
---

The Next.js adapter authorizes actions and Server Components, signs out ended sessions and scopes cache tags to a tenant.

- `bs.action()` and `bs.route()` take `requireTenant` and `authorize(session, input)`, and `bs.require(options)` refuses a Server Component caller with `unauthorized()`, `forbidden()` or `notFound()`.
- `bs.proxy(request, { endedSession })` asks Auth whether the session still exists and clears the cookies when it doesn't, and `expiredPrefetch: "render"` renders a prefetch with an expired token signed out.
- `bs.cacheTag`, `bs.cacheTags` and `bs.cached` take `{ tenant }`, so a mutation in one tenant no longer revalidates other tenants' reads, and `bs.context({ tenant })` takes the tenant from route params.
- Mutations outside a Server Action expire tags with `{ expire: 0 }`, so a read after a write in a route handler is fresh (`nextCache({ revalidate })` keeps `"max"`).
- `useSessionChange` refreshes the session before an organization switch re-renders, and `tenantOf(session)` reads the active tenant.
- **Breaking:** the `next` peer range is `>=16.3 <17`, because `createNext` awaits `io()`. Upgrade Next.js first.

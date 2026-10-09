---
"better-supabase": minor
---

Every server adapter now has the guards and actions the Next.js adapter has.

- `createSvelteKit`, `createReactRouter` and `createTanStackStart` build a server with a `handle` hook or middleware that puts `db`, `bs`, `auth`, `tenant` and the serializable `session` on the request. `bs.require()` returns the caller in a load, loader or server function, or refuses it with a redirect to `signIn` or `mfa`, else Problem Details. `bs.action()` validates the input with any Standard Schema, runs `requireTenant` and `authorize`, and returns an `ActionResult`. SvelteKit also gets `handleError` and `depends(load, ...tables)`.
- Hono gets `bs.require()` route middleware, and `c.var.session` and `c.var.tenant`. Elysia and H3 export `guard()` and `problemOnError()`.
- `bs.routes({ 'GET /customers/:id': handler })` on the edge routes by method and path, with a guard per route, and answers unknown paths with 404 and other methods with 405 before auth resolves.
- `bs.authed(options)` in oRPC is `os` with the caller's context, and takes `requireTenant` and `authorize`. `fetchHandler` passes the Workers `executionContext.waitUntil` to event sends.
- `createMcp` takes `requiredRoles`, a list of roles or `{ roles, claim }`, and refuses callers without one.
- `better-supabase/server` exports `shouldRefresh`, `shouldCheckSession` and `isPrefetch`; the session entry's `refresh` takes `'navigation'` or a predicate, so parallel script fetches no longer race on the single-use refresh token. `withServerTiming()` adds a `Server-Timing` header and `ctx.timing`, and `withDbStats()` adds the request's database calls as `x-bs-db-calls`.
- `tagFor`, `cacheTagsOf` and `tagCache` build a `CacheAdapter` for any tag-based cache.
- `expectDbBudget(response, { maxCalls })` in `better-supabase/testing` checks the `withDbStats()` header of any fetch response.

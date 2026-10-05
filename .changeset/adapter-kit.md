---
"better-supabase": minor
---

Adapters share one request path, and you can build your own on it. `better-supabase/server` exports `handle(server, request, run, options)`, which resolves the caller, applies the guard, answers the handler's value as JSON or Problem Details, adds the context's cookies and hands pending event sends to `waitUntil`. It also exports `extendServer`, `flushEvents`, `unexpectedResponse` and `resolveToken(server, token)`. `ctx.cookies()` lists the cookies `ctx.apply()` would set, and `server.events` is the definition's event hub. `testAdapter` in `better-supabase/testing` checks an adapter against the same contract, and the first-party adapters run it.

The Edge, Expo and Next.js route handlers now use `handle()`. The Hono middleware, oRPC's `fetchHandler`, `createMcp` and `createMcpAuth` take a `waitUntil` option and pass it pending event sends; Hono also uses `c.executionCtx.waitUntil` on Workers. Before, only Next.js and Edge did. The Next.js support cookie's `Max-Age` now rounds up, as `supportCookie()` does.

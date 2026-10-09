---
"better-supabase": minor
---

Adapters for more server frameworks, typed structurally, with the guards and actions of the Next.js adapter. They replace the `@supabase/server` framework adapters, which upstream removes on 2026-12-01.

- New subpaths: `better-supabase/tanstack-start`, `/sveltekit`, `/react-router`, `/h3`, `/h3/v1`, `/elysia`, `/node` (`toExpress`, `toFastify`, `toKoa`), `/nestjs` (`@nestjs/common` is an optional peer), `/astro`, `/nuxt` and `/solid-start`. `toHono`, `toEdge`, `toOrpc` and `toExpo` bridge the existing adapters.
- Each factory puts `db`, `bs`, `auth`, `tenant` and `session` on the request, with `bs.require()` and `bs.action()`; every guard takes `roles` and `roleClaim`. The edge gets `bs.routes({ "GET /customers/:id": handler })` with typed `ctx.params` (`RouteParams`), oRPC gets `bs.authed()`, and `createMcp` takes `requiredRoles`.
- `handle()`, `extendServer`, `flushEvents` and `resolveToken` build an adapter on the shared request path, checked by `testAdapter`. `withServerTiming()`, `withDbStats()` and `tagCache` cover timing headers, database budgets and tag caches.
- **Breaking:** `createEdge`'s `cors` option runs `withCors` from `@supabase/middleware/cors`. A preflight needs `Access-Control-Request-Method` (other `OPTIONS` requests reach the handler), and an allow-list adds `Vary: Origin`. `corsConfig(options)` returns the config.

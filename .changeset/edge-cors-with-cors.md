---
"better-supabase": minor
---

`createEdge`'s `cors` option now runs `withCors` from `@supabase/middleware/cors`. Two details change: a preflight is an `OPTIONS` request that carries `Access-Control-Request-Method` (browsers always send it; an `OPTIONS` request without it reaches the handler), and an allow-list adds `Vary: Origin` with a capital `O`. `corsConfig(options)` returns the `withCors` config for a custom pipeline, and `SUPABASE_CORS_HEADERS` stays exported.

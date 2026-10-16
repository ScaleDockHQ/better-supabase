---
"better-supabase": minor
---

Add `rateLimit()` middleware to the Hono and oRPC adapters, built on `createRateLimit`. Responses carry the
`RateLimit` and `RateLimit-Policy` fields of draft-ietf-httpapi-ratelimit-headers-11, and a refused request gets a
429 with `Retry-After`. `better-supabase/server` exports `rateLimitHeader()` and `rateLimitPolicyHeader()`.

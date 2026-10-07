---
"better-supabase": minor
---

`createRateLimit` accepts a `BlockTransport` as well as a SQL client, so an app without a direct Postgres connection limits route handlers over the Data API with `createRateLimit(rpcTransport(adminClient))`. The `rate-limit` module adds `check_rate_limit(scope, key, max_requests, period)`, a service-role function that returns the decision as JSON for transports, and `createRateLimit` takes `mappers` for its errors.

---
"better-supabase": minor
---

The `rate-limit` module limits route handlers too: `hit_rate_limit(scope, key)` counts a hit of any key (a public token, an organization, a chat thread) against the scope's rule or a per-call limit, and `createRateLimit(sql).check(scope, key)` and `rateLimited(decision)` from `better-supabase/blocks/jobs` call it and answer a `problem+json` 429 with `Retry-After`. `purge_rate_limits` keeps counters without a rule for a day.

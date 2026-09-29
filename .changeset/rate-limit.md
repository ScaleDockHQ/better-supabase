---
'better-supabase': minor
---

Write rate limits: the `rate-limit` SQL kit module adds `set_rate_limit(scope, max, period, key_claim)` and a `pgrst.db_pre_request` hook that counts Data API writes (POST, PATCH, PUT, DELETE) per user or claim and answers over-limit requests with 429 and `Retry-After`. The new `rate_limited` `DbError` kind (429) carries `retryAfter`, and `problemResponse()` sets the `Retry-After` header.

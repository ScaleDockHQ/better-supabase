---
"better-supabase": minor
---

Usage keeps who and what used a meter. With `sql.modules.usage.options.history`, every recorded quantity also goes to `usage_history` with the caller's user id (or `actor`, for a service transport), a `source` and `metadata`. `usage.history(organizationId, { meter, limit, before })` pages through it and `usage.breakdown(organizationId, meter)` sums the current window per actor and source, both for `usage.read`; `purge_usage_history` deletes old entries. `record_usage` and `consume_quota` take `source`, `metadata` and `actor`.

---
"better-supabase": minor
---

A `usage_quotas` row with a `null` limit is an unlimited quota. It wins over every limited plan row and a tenant row with a `null` limit lifts the plan limits for that tenant, so a plan or a tenant can be exempt from a meter's quota while it still sets the meter's period. `usage.current()` returns `unlimited: true` (and `usage_status` an `unlimited` field), `consume` and `within_quota` always pass, and `reportUsageToStripe({ overage: true })` sends nothing for an unlimited meter.

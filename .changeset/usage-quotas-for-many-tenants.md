---
"better-supabase": minor
---

The usage module adds `usage_quotas_for(tenants, meters)`, which returns the
quota of every tenant and meter pair and resolves each tenant's entitlements
and plans once. The usage block's admin client calls it through
`usage.quotas({ organizationIds, meters })`, which returns one `UsageQuota`
per pair that has a quota. `usage_quota(tenant, meter)` now reads from it and
returns the same row as before.

Run `better-supabase upgrade` (usage 9).

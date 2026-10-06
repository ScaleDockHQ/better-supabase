---
"better-supabase": minor
---

With `entitlements.source` set to a plan catalog, the entitlements module writes `better_supabase.tenant_plans(tenant)` (the tenant's active plan keys), and usage quotas match a plan row by the tenant's plan key as well as by its entitlement keys, so `('pro', 'api_calls', 50000, 'month')` applies to every tenant on `pro`.

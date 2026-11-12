---
"better-supabase": patch
---

`unreported_usage` reads each tenant's plans and entitlements once and each quota once per tenant and meter, instead of once per counter row, and computes each window start once per tenant, period and day. On 1,000 counters of 20 tenants it calls `tenant_entitlements` 20 times instead of 1,008 and `usage_window_start` 102 times instead of 1,000.

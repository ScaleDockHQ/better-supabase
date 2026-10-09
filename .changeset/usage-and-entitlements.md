---
"better-supabase": minor
---

The usage block (`better-supabase/blocks/usage`) meters fractional quantities against quotas that follow the plan or billing cycle, and entitlements read from any plan catalog.

- Quantities and limits are `numeric`, `recordMany` and `consumeMany` record several meters all or none, and a `null` limit is unlimited.
- `options.meters` is a meter catalog in the config or a table, read by `usage.meters()`, `overview(organizationId)` and `current()`. `options.history` keeps each record, read by `history` and `breakdown`. Reading needs `usage.read` and recording `usage.record`.
- The `billing` period follows `usage_billing_period(tenant)`, and `reportUsageToStripe({ overage: true })` sends only usage above the quota.
- `entitlements.source` reads features from your plan tables or `"custom"`, with values through `entitlement_value`, and `entitlements.claim` sets the claim's shape (`EntitlementClaimOptions`).

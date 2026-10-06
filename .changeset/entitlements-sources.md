---
"better-supabase": minor
---

The `entitlements` module reads from other sources than the Stripe Sync Engine: `entitlements.source: { plans }` derives each tenant's features from a plan catalog in your tables (the active subscription's plan and the features it includes), and `source: "custom"` leaves `tenant_entitlements(tenant)` to the app while the module writes `has_entitlement`, `tenant_ids_with_entitlement` and `feature_claims` over it. Neither needs a Stripe customer column.

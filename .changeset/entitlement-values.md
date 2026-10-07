---
"better-supabase": minor
---

Entitlements carry feature values. With a plan catalog, `entitlements.source.plans.features.value` names a column with each feature's value (a number, text or `jsonb`), and the module writes `better_supabase.tenant_entitlement_value(tenant, key)` (service role) and `entitlement_value(tenant, key)` (members of the tenant). They return the value as `jsonb`, the largest number when several active plans set it, `true` for a feature without a value, and null without the feature, so a tier such as "30, 90 or 365 days of history" needs no parsing from the feature key. The Sync Engine source returns `true` or null. In custom mode the app writes `tenant_entitlement_value` next to `tenant_entitlements`.

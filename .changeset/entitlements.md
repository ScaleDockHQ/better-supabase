---
'better-supabase': minor
---

Add the `entitlements` SQL kit module over the Stripe Sync Engine
(`SPEC_PINS.stripeSyncEngine`, 0.48.5): `tenant_entitlements()`,
`has_entitlement()` for RLS, `membership_claims()` for the access token hook's
`memberships[].entitlements`, and `entitlement_members()`. The Stripe customer
column is set with the new `entitlements` config key. `hasEntitlement(session,
tenantId, key)` is typed from `sb.claims()`, and `better-supabase/jobs` adds
`ENTITLEMENTS_UPDATED` and `entitlementMembers()` for invalidating sessions
after `entitlements.active_entitlement_summary.updated`.

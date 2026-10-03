---
"better-supabase": patch
---

In PermDock mode, the `entitlements` kit module renders the tenant argument of `has_entitlement`, `tenant_entitlements` and `tenant_stripe_customer`, and the rows of `stripe_customer_tenants`, with the scope's id type from the manifest's `rls.scopes` (`uuid`, `text` or `bigint`) instead of always `uuid`. A missing or other type stops `sql add entitlements` and doctor BS408 reports it. `better-supabase/sql` exports `KIT_ID_TYPES`, `isKitIdType` and the `KitIdType` type, and `KitPermdock` has a required `idType`.

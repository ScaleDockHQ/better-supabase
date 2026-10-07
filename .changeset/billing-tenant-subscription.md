---
"better-supabase": minor
---

The billing module adds `better_supabase.billing_tenant_subscription(tenant)`, the tenant's newest synced subscription without a check of the caller, for an app's own `security definer` functions, such as one that resolves an ordinary member's plan. No role is granted it, so only functions owned by the module's owner call it, and `api` writes no entry point for it. `billing_subscription` now checks the caller and calls it.

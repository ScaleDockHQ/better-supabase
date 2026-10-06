---
"better-supabase": minor
---

`billing.subscription(organizationId)` reads the tenant's newest subscription in full (every Sync Engine column, with its `items`), and `billing.allSubscriptions({ status, limit, before })` reads every tenant's newest subscription for platform staff, as `{ organizationId, customerId, row }`. The `billing` module adds `billing_subscription` and `billing_all_subscriptions`, and a `viewAll` permission (platform scope, `billing.read` by default) that both check.

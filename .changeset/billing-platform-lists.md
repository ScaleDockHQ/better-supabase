---
"better-supabase": minor
---

The `billing` module adds `billing_platform_subscriptions()` and `billing_platform_invoices()`, set-returning functions with typed columns (tenant, customer, subscription, status, price, plan from `options.plans`, quantity, amount, currency, current period end, cancel at period end and created; invoice number, amounts, due date and created) over the Stripe Sync Engine's tables. An admin list can join them to the tenant and plan tables, filter, sort and count in SQL. They are open to the service role and platform staff with the module's `viewAll` permission. `allSubscriptions()` and `allInvoices()` keep returning the raw rows.

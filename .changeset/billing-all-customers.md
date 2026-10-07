---
"better-supabase": minor
---

The billing module adds `better_supabase.billing_platform_customers()`, every linked Stripe customer with `tenant`, `customer`, `email`, `name` and `created` as typed columns, so an admin list can show tenants without a subscription or invoice. It is open to the service role and platform staff with `viewAll`. `billing.allCustomers()` reads it through `billing_all_customers()` and returns `BillingCustomer` objects.

---
"better-supabase": minor
---

The `entitlements` module reads the Stripe customer from the `billing` or `organizations` module through their configured names: a renamed `billing_customers` table, its `customer` and `tenant` columns, or an `organizations` table in another schema or with another id column now resolve correctly instead of falling back to `stripe_customer_id`, `organization_id` and `better_supabase.organizations`. `entitlements` lists both modules in `integrates`.

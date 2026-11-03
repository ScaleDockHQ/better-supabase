---
"better-supabase": minor
---

`billing` keeps subscriptions in Postgres: `billing_native_subscriptions` holds a plan, a price in minor units, a quantity and the period, independent of Stripe. `create_native_subscription`, `prorate_change` and `cancel_native_subscription` are service-role functions, and `createNativeSubscriptions` in `better-supabase/blocks/billing` calls them. `prorate_change` returns the credit, charge and net of a mid-period change and, with the `ledger` block installed, posts the net as one `billing.proration` transaction. Existing apps run `better-supabase db diff` to pick up the new table and functions.

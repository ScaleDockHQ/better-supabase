---
"better-supabase": minor
---

`billing_platform_subscriptions()` returns the customer's `customer_email` and `customer_name` from `stripe.customers` and the price's Stripe metadata as `price_metadata`, so a plan lookup can fall back to a key kept there. `billing_platform_invoices()` returns `finalized_at` from the status transitions, `customer_name`, and `updated_at`, the time the Sync Engine last wrote the row; `customer_email` and `customer_name` fall back to the customer's when the invoice has none.

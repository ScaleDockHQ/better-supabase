---
"better-supabase": minor
---

`billing_platform_invoices()` returns `amount_remaining`, `paid_at`, `hosted_invoice_url`, `invoice_pdf` and `customer_email`, and `billing_platform_subscriptions()` returns `current_period_start` and the price's `recurring_interval`, all read from the Stripe Sync Engine's tables, so an admin list can link to the hosted invoice and show the billing period without calling Stripe.

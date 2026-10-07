---
"better-supabase": minor
---

The billing module reads tax ids from the Stripe Sync Engine. `better_supabase.billing_tax_ids(tenant)` returns the tenant customer's `stripe.tax_ids` rows as `[{ id, type, value, country, verification: { status }, created }]`, newest first, for callers with `billing.read` or platform staff, and `[]` before the tenant has a customer or the table exists. `billing.taxIds(organizationId, { from: "sync" })` reads it in the same `StripeTaxId` shape as the Stripe call, and `billing_stripe_rows` accepts `tax_ids` as a source.

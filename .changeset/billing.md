---
"better-supabase": minor
---

The billing block (`better-supabase/blocks/billing`) runs a tenant's Stripe subscription over the Stripe Sync Engine and gives platform staff typed lists across tenants.

- `changePlan`, `cancelAtPeriodEnd`, `invoices`, `paymentMethods`, `voidInvoice`, `customerDetails`, `updateCustomer` and tax ids (`StripeTaxId`).
- `options.plans` points at your plan catalog with price `variant`s, and `checkout` merges `params` deeply.
- Staff with `viewAll` read `allSubscriptions`, `allInvoices` and `allCustomers`, also as `billing_platform_*` SQL functions.
- `StripeSource` accepts a function that returns a client, and `ensureCustomer` is idempotent per organization.

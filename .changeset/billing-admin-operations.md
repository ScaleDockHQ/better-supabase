---
"better-supabase": minor
---

The billing block covers the admin side of a subscription: `changePlan`, `cancelAtPeriodEnd`, `invoices` and `paymentMethods` (read from the Stripe Sync Engine as the caller with `billing.read`), `voidInvoice` and `markInvoiceUncollectible` for the tenant's own invoices, and `customerDetails` and `updateCustomer` for the billing contact, which stays on the Stripe customer. `sql.modules.billing.options.plans` points at the app's plan catalog, so `checkout({ plan, interval })` and `changePlan({ plan })` take a plan key. The structural `StripeClient` gains optional `subscriptions.update`, `customers.update` and `invoices`; the docs show a plan-based `audit_retention` function.

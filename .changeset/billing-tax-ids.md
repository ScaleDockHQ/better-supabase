---
"better-supabase": minor
---

`billing.taxIds`, `billing.addTaxId` and `billing.removeTaxId` read and write the tax ids (VAT, GST and the other Stripe types) on the tenant's Stripe customer; `addTaxId` creates the customer when the tenant has none. `StripeClient.customers` gains the optional `listTaxIds`, `createTaxId` and `deleteTaxId`, and `StripeTaxId` is exported.

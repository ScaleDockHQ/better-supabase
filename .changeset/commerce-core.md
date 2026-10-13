---
"better-supabase": minor
---

Add `better-supabase/blocks/commerce`. It holds money as a `bigint` count of the currency's minor units, using ISO 4217 List One (pinned as `SPEC_PINS.iso4217`), with arithmetic, half-to-even rates, allocation, parsing, formatting and JSON. It also defines the versioned `PaymentProvider` and `TaxProvider` interfaces. `stripePayments` implements the first on Stripe PaymentIntents and webhooks. `stripeTax` and `fixedRates` implement the second. `better-supabase/testing` adds their conformance kits, `testPaymentProvider` and `testTaxProvider`.

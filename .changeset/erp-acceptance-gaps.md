---
"better-supabase": minor
---

With the legal entities block and `options.on` listing `invoices`, `quotes` or `orders`, their
numbers are now unique per legal entity, so two entities can both hold `INV-0001`. An issued
invoice's header total now includes the payment-term credit restriction, as its tax lines do.

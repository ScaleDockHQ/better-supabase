---
"better-supabase": minor
---

`StripeSource` (the `stripe` option of `createBilling` and the usage block's Stripe reporting) accepts a function that returns a Stripe client, sync or async. It runs on every Stripe call, so apps create the client lazily, read a rotated key, or pick a per-request client such as a Stripe Connect account.

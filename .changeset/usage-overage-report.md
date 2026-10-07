---
"better-supabase": minor
---

`reportUsageToStripe({ overage: true })` sends only the usage above each tenant's quota in its quota window, for plans that include an allowance; usage inside the quota is marked reported without a meter event. `unreported_usage` returns each counter's `included` quota and `window_before` usage for the calculation.

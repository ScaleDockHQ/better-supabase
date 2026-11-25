---
"better-supabase": minor
---

The banking block records `payment_batch.created`, `payment_batch.posted` and `payment_batch.cancelled`, each with an audit entry, so every payout batch leaves a trail of who created, posted or cancelled it. Run `better-supabase upgrade` to regenerate the banking module.

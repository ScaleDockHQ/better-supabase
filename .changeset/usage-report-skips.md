---
"better-supabase": minor
---

`reportUsageToStripe` no longer stalls on counters it can't send. A meter without an event name or a tenant without a Stripe customer used to stay at the front of every batch, so a large enough backlog of them blocked every other counter. The report now asks `unreported_usage` again with those meters and tenants left out (its new `skip_meters` and `skip_tenants` arguments), so each run fills its batch with counters it can send. The `usage` module moves to version 3; `sql upgrade` drops the old `unreported_usage(integer)` signature, and a `custom` usage module implements the new one.

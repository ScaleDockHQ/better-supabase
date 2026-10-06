---
"better-supabase": minor
---

`usage.recordMany` and `usage.consumeMany` record several meters in one transaction, all or none, such as the input and output tokens of one call; `consumeMany` checks each quota first and records nothing when one doesn't fit. The idempotency key covers the batch. The `usage` module adds `record_usage_batch(tenant, entries, idempotency_key, check, source, metadata, actor)`.

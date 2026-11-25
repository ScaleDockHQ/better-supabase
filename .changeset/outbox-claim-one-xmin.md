---
"better-supabase": patch
---

`outbox_claim` reads the oldest running transaction once per call, so an event that commits between the claim's read and its cursor move is no longer skipped when the consumer's types match nothing in the batch. Run `better-supabase upgrade` to regenerate the outbox module.

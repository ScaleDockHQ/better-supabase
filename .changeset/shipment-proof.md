---
"better-supabase": minor
---

Shipments (module version 4) record the proof of delivery: `recordProof` stores `deliveredTo`, a `proofReference` and a `proofAttachmentId` once for a delivered shipment and emits `shipment.proof_recorded`. A carrier can add the optional `proofOfDelivery` method. Tracking events are append-only: a trigger refuses edits and deletes with `SHIPMENT_EVENTS_APPEND_ONLY`, except in a tenant purge.

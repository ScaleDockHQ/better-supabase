# 0240: Record proof of delivery and keep tracking events append-only

- Status: accepted
- Date: 2026-11-05

## Context

A delivered shipment held a status and a timestamp. Notices that need proof of
delivery (certified mail, a signed receipt) had nowhere to keep who received
the parcel or the carrier's reference, and tracking events could be edited
through a custom role.

## Decision

The shipments module (version 4) adds `delivered_to`, `proof_reference`,
`proof_attachment_id` and `proof_recorded_at`, all optional names, and
`record_delivery_proof`, which writes them once for a delivered shipment and
emits `shipment.proof_recorded`. The attachment is a plain uuid; the app
links it through the attachments block. Tracking events get a trigger that
refuses updates and deletes, with the data-lifecycle tenant purge as the only
way out, as on the ledger.

`ShippingProvider` gains an optional `proofOfDelivery(trackingNumber)`, so
`recordProof` can take the proof from the carrier. Certified mail is a
`service` value, not a new column.

## Alternatives considered

- A foreign key to attachments. It would make the attachments block a hard
  requirement of shipments.
- Replacing the cascade with `restrict`. A tenant purge would then depend on
  the order of deletes; the trigger already protects the events.

## Consequences

`record_delivery_proof` is client-callable by members who may manage
shipments. Apps that deleted tracking events directly now get
`SHIPMENT_EVENTS_APPEND_ONLY`.

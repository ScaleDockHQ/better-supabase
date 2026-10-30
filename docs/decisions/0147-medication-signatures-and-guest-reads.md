# 0147: Sign medication records and let guests read them

- Status: accepted
- Date: 2026-10-30

## Context

Medications had no way to bind a prescriber's or nurse's signature to an order
or a dose, no extra columns on the catalog and dose tables, and no read path
for the family or resident a record is shared with.

## Decision

- `approve_medication_order(order_id, signature_id)` and an optional
  `signature_id` on `record_medication_administration` store the signature on
  the row. The signature must be the caller's, completed, in the same
  organization and on the record (`medication_order` or
  `medication_administration`, keyed by the row id).
- `medicationExtraColumns` and `administrationExtraColumns` add extra columns
  to the catalog and dose tables; `fields` carries them through the save and
  record functions.
- `guestRead` adds `ctx.scope.guest` branches to the read policies of orders,
  doses and medications. Read functions are security invoker, so guests use
  them unchanged.

## Alternatives considered

- **New events for signing.** The existing update events already carry the row.
- **Guest write access.** Giving a guest a dose or order write path conflicts
  with the member checks every function makes.

## Consequences

- `record_medication_administration` gains arguments, so the migration drops
  and recreates it; clients regenerate their bindings.
- Without the `signatures` block a signature id is refused.

# 0268: Close the parties and documents gaps of the base layer

- Status: accepted
- Date: 2026-11-07
- Amends: 0157

## Context

Part 5 of the declarative base layer plan lists what an app wrote beside the
parties and documents blocks. An audit found orders from a quote (with
`kitchen` off by default), webhook endpoint create, update, list and delete,
section lines, and numbering `scope` and `period` already shipped. The rest was
open, and the plan names several items without saying where they live.

## Decision

- Contacts: `people.mode` (`external` by default, or `tenant`, which needs a
  user) and the company columns `legal_name`, `registration_id` and `phone`.
  All are optional columns an app can map to null. The plan says "person modes"
  and "company fields"; the simplest reading is one mode column and the three
  fields a CentraKit company table added.
- Lines of a document (quote lines, so quote versions too): `periods` may be
  null for a subscription line with no end, `unit` says what a unit is (the
  plan's "rate units"), and `discount_kind` (`percentage` or `fixed`) is the
  "discount cast": over an app table it takes the app's enum through
  `ctx.cast`, and a key a line leaves out takes the column default. A line that
  leaves out `unit` or `discountKind` keeps the value it had on an update, as
  an extra column does. Time rates stay per hour; a rate unit there would
  change every invoice quantity.
- Optional lines already existed (`optional`, `selected`), so nothing is added.
- `uniqueNumber` is no longer an option on invoices. An invoice is unique by
  tenant, direction, kind and identifier (the number when the table has no
  identifier column), which holds when numbering restarts each period. The
  `false` setting is gone: numbering per kind and direction is the rule.
- `shipments.direction` (`outbound` or `inbound`) with `set_shipment_direction`
  for a draft. A new function keeps `create_shipment` as it is, so callers
  need no change.
- Letterheads are a seed of document-templates, not a table: one `letterhead`
  text block per locale (`nl`, `de`, `fr`), applied by `seed_tenant_defaults`.
- The `purchase_order` document type reads inventory purchase orders: the
  supplier is the buyer, the lines are ordered quantities at their unit cost,
  and the number is `PO-` and eight characters of the order id, because the
  purchase order table has no number. The contract version stays 1: a new type
  adds optional keys only.

The `set_shipment_direction` and `seed_document_templates_defaults` functions
are security definer, like their neighbours: signed-in users have no grant on
the shipment tables, and the seed runs for the service role. The baselines go
from 69 to 75 (shipments) and from 55 to 61 (document-templates), counting the
api wrappers.

## Consequences

An app that added `legal_name`, `unit`, `discount_kind` or a shipment direction
as its own column on a block-owned table must delete its column and run
`upgrade`; over its own table the block reads the column it already has.

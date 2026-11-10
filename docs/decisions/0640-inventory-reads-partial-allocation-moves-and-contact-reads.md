# 0640: Read inventory levels and movements from the client, move allocations in parts, and read one contact by id

- Status: accepted
- Date: 2026-11-10
- Amends: 0127, 0267

## Context

The performance audit listed inventory leads from CentraKit's gap log: a set-based levels read, a
movement list, partial release and transfer of an allocation. The levels and movement list already
ship as SQL functions (`inventory_levels`, `list_inventory_movements`), but the inventory client had
no method for them, so an app either looped `stock_detail` per variant or wrote its own query. The
example's `loadContact` still paged through up to ten lists because it predated `getCompany` and
`getPerson`.

## Decision

**Client reads.** `inventory.levels({ organizationId, variantIds?, locationId? })` and
`inventory.movements({ organizationId, variantId?, locationId?, binId?, lotId?, documentType?,
documentId?, limit?, offset? })` call the existing functions. A variant list reads levels by their
primary key, so a page of products is one query. The result types are `StockLevelRead` and
`StockMovementRead`; quantities stay text.

**Partial moves.** `release_allocation(allocation, quantity default null)` and
`transfer_allocation(allocation, document_type, document_id, line_id default null, quantity default
null)` take an optional quantity. A quantity equal to what the allocation has left, or none, keeps
the whole-allocation behavior. A smaller quantity on a release lowers the allocation's `quantity`,
frees backorder first and then held stock, and refills waiting backorders. A smaller quantity on a
transfer splits the allocation: the held stock moves first into a new allocation on the new
document, and the call returns that allocation. A quantity of zero or more than is left fails with
`INVENTORY_QUANTITY_INVALID`. The events carry `released` and `transferred` quantities.

**Contact read.** The example reads a contact with `getCompany` and `getPerson` in parallel.

## Alternatives considered

- Declare `inventory_levels` as a block read: reads have no uuid array argument type, and a typed
  result is all the client needs.
- Split on release by creating a released row for the freed part: it keeps history but doubles the
  rows for a common operation, and the event already records the quantity.

## Consequences

Dropping the old one-argument and four-argument overloads is part of the migration, so a caller that
passes positional arguments through PostgREST keeps working (the new arguments have defaults).

Server bundle growth: the two client methods and the optional quantity put about 875 bytes of raw
JavaScript into every route that carries the block set (139 routes grow by about 550 to 830 bytes
each depending on the route; gzip and brotli stay inside their slack). The guard allows 512 bytes.
The methods are trimmed to null defaults and a plain read descriptor, and the rest is the code
itself (two calls with their argument maps and result descriptors), so trimming further would mean
dropping the typed result checks. The maintainer approved raising the baselines by hand, as #804
did. `tests/next-build/server-baseline.json` holds main's per-route values plus this change's delta
(for example `/[locale]/(app)/appraisals/page` 2,826,655 raw on main, then +824); CI passes the
server guard with them. `tests/next-build/next-build.test.ts` and the never-grows guard are
unchanged. In `tests/next-build/baseline.json` CI measured three first-load brotli values over
their slack, so those were raised to the measured values: `/[locale]/(app)/assistant/tasks/page`
358,657 to 359,557, `/[locale]/(app)/shop/orders/[id]/page` 372,568 to 373,523 and
`/[locale]/(app)/shop/page` 371,425 to 372,363.

Not done in this change, listed in the plan: `import_allocation`, a purchase order number, tax lines
and a canceled quantity on purchase orders, sales order `draft` and `on_hold`, historical quote
import on a status-guarded table, banking primary and holder columns, and batch reads for assistant
run steps, project versions, hiring applications, templates and FHIR care plans. Each needs its own
SQL, fixture regeneration and pgTAP file.

The inventory read helpers (`blocks/inventory/reads.ts`) add server code to every route that imports
the blocks. The raw server baseline of 139 routes in `tests/next-build/server-baseline.json` rose
by about 820 bytes each (0.03 percent of a route); the numbers are re-measured from a fresh build of
this branch after merging main. The guard in `next-build.test.ts` is unchanged.

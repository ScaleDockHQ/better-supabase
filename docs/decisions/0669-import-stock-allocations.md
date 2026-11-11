# 0669: Import stock allocations

- Status: accepted
- Date: 2026-11-10

## Context

A migration from another system brings documents that already hold stock: open sales orders with
units set aside, and shipped or released lines. The inventory block had import targets for stock
counts only, so an imported order's allocations had to be recreated through `allocate_stock`, which
takes available stock now and changes the reserved total by what it finds, not by what the source
system held. The plan called the missing target `import_allocation`, but the invoices block already
owns that name for payment allocations, with the same arguments.

## Decision

The inventory block contributes a `stock_allocation` import target, written by
`import_stock_allocation(run, item, subject_id)` with `stock_allocation_updated_at` for the conflict
check. The item data is the variant (`variantId` or `sku`), the location (`locationId` or a `location`
code), `documentType`, `documentId`, an optional `lineId`, `quantity`, the parts `allocated` and
`fulfilled`, and a `status` of `open`, `fulfilled` or `released`. The row is stored as given. An open
allocation adds what it holds to the location's `reserved` stock; a fulfilled or released one holds
nothing, and a fulfilled one counts its whole quantity as fulfilled. No stock movement and no event
is written, in line with ADR 0141, so the source system's stock comes in through its own import.

A later run with the same key replaces an open allocation, and first takes back the reserved stock
the old values held. A fulfilled or released allocation is kept as imported and reports
`IMPORT_DOCUMENT_CHANGED`.

## Consequences

An import can set aside more than is available, since it records the source system's state and
doesn't check it; `fill_backorders` and `fulfill_allocation` work on the rows as usual afterwards. The
function is named `import_stock_allocation`, so the invoices block's `import_allocation` is untouched.

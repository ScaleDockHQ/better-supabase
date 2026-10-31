---
"better-supabase": minor
---

New `rfqs` block (`better-supabase/blocks/rfqs`): requests for quotation sent to suppliers, their quotes side by side, and an award that creates a purchase order.

- `createRfq`, `updateRfq`, `getRfq` and `listRfqs` keep numbered requests (`RFQ-1`) with lines that move from draft to open, closed and awarded or cancelled.
- `inviteSupplier` and `declineInvitation` name suppliers by party type and id. With the contacts block the party must be an active supplier.
- `recordQuote` stores a supplier's unit prices and revises them in place. `withdrawQuote` takes a quote out of the comparison.
- `compare` lists the live quotes cheapest first and marks the best unit price per line.
- `award` rejects the other quotes and, with the inventory block and a `location`, creates a draft purchase order at the quoted prices.
- The permission keys are `rfqs.read`, `rfqs.write` and `rfqs.manage`.

Run `better-supabase add rfqs` and generate a migration.

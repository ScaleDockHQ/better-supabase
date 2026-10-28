---
"better-supabase": minor
---

Inventory counts fractional units with lots, serials, expiry, bins and average cost; orders come from lines or a quote; and shipments carry stock (ADR 0126).

- `setStockItem(variantId, { unit, scale, tracking, tracksExpiry, costing, currency })` gives a variant a unit with up to 6 decimals, lot or serial tracking and weighted average cost. The ledger posts base units (the quantity times ten to the scale).
- Every movement takes a `detail` with `binId`, `lotId` or `lot` and `serials`. `saveBin` (with `hold` bins), `saveLot`, `stockDetail`, `expiringLots`, `expireLots` and `stockValuation` read and age the stock. Stock leaves first-expiry-first-out, and sales skip hold bins and expired lots.
- `allocate`, `fulfillAllocation`, `restoreAllocation`, `releaseAllocations` and `listAllocations` hold stock for a document line in `stock_allocations`, with backorders that fill as stock arrives. Events: `allocation.created`, `allocation.filled`, `allocation.released`.
- `orders.fromLines(organizationId, input)` and `orders.fromQuote(quoteId)` make a `confirmed` order, once per origin or quote, and allocate its lines. `orderFromQuoteAction` calls `orders.fromQuote` when you pass no `create`.
- `shipments.setLines(id, lines)` and `shipments.receiveReturn(id, lines)` with the new `shipment_lines` table: the label takes the lines out of inventory, cancelling puts them back, and returns are restocked, held or scrapped (`shipment.return_received`).

Breaking changes:

| Before                                                    | After                                                            |
| --------------------------------------------------------- | ---------------------------------------------------------------- |
| integer stock columns and functions                       | `numeric(20, 6)`; `available` is on hand minus reserved and held |
| `before_stock_adjust(uuid, uuid, integer, text)`          | `before_stock_adjust(uuid, uuid, numeric, text)`                 |
| `before_stock_reserve(uuid, uuid, integer, text, text)`   | `before_stock_reserve(uuid, uuid, numeric, text, text)`          |
| `move_stock(..., quantity integer, ...)`                  | `move_stock(..., quantity numeric, ..., detail jsonb)`           |
| `OrderStatus` without `confirmed`                         | `confirmed`, the first status of an order from a document        |
| `orderFromQuoteAction({ create })` with `create` required | `create` optional                                                |
| `Shipment` without `lines`                                | `Shipment.lines`                                                 |

Raw SQL reads of the stock columns now return decimal strings such as `"7.000000"`, and stock event payloads carry them the same way (`available`, `reorderPoint`).

`better-supabase codemod 0.35` lists the stock hooks declared with an `integer` quantity, the order status switches and `orderFromQuoteAction` calls for review.

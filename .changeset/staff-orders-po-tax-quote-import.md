---
"better-supabase": minor
---

Orders take two staff states. Pass `draft: true` to `orders.fromLines` or `orders.fromQuote` to save an order that holds no stock, then `orders.confirmDraft` to allocate its stock and place it. `orders.hold` puts an order that waits for payment, or a confirmed one, on hold and `orders.releaseHold` returns it to the status it was held from; `Order` returns `heldAt` and `holdReason`, and the events are `order.drafted`, `order.hold_placed` and `order.hold_released`. Purchase order lines take `taxRateBps` and `taxCode`, `savePurchaseOrder` rebuilds the order's tax lines, and `inventory.purchaseOrderTaxLines` reads them. A historical quote import with `update: "apply"` now replaces the lines of a sent or decided quote and applies its stored tax lines and totals. Run `better-supabase upgrade` to add the `held_at`, `held_from`, `hold_reason` and `tax_rate_bps` columns and the `purchase_order_tax_lines` table.

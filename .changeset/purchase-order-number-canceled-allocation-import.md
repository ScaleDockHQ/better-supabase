---
"better-supabase": minor
---

Purchase orders take a `number` on `savePurchaseOrder` (an order without one gets the next all-digit number when it is placed) and `cancelPurchaseOrderQuantity` gives up part of what a placed order still owes. The units stop counting as incoming, receipts and the backorder count leave them out, and the event is `purchase_order.line_cancelled`. The inventory block also contributes a `stock_allocation` import target, written by `import_stock_allocation`, for the stock a source system's documents held. Run `better-supabase upgrade` to replace `save_purchase_order` and add the new functions.

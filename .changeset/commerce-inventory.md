---
"better-supabase": minor
---

Add the inventory block (`better-supabase/blocks/inventory`) and its `inventory` SQL module: locations, stock levels per catalog variant and location kept by an append-only movement ledger, reservations that expire (lazily and through a service-only `expire_reservations` job), transfers between locations and purchase orders with partial receiving and backorders. It emits `stock.*`, `reservation.*`, `transfer.*` and `purchase_order.*` events, and the catalog refuses to delete variants with stock history.

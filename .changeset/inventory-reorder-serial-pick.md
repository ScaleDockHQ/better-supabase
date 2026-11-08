---
"better-supabase": minor
---

The inventory block gets `stock_levels.reorder_quantity` with `setReorderQuantity`, the SQL function `pick_serials(variant, location, quantity, lot)` with `pickSerials`, which chooses the oldest serial numbers in stock, and a unique `(id, tenant_id)` on locations, reservations, transfers and purchase orders so your tables can reference them with a composite key. They replace app SQL that added the column, picked serials and added the constraint. Run `better-supabase upgrade` and generate a migration with `supabase db schema declarative sync`.

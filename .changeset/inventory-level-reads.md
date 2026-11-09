---
"better-supabase": minor
---

`inventory_levels` reads stock for the variants you pass, and `inventory_status_counts` and `list_inventory_movements` read the status totals and the stock ledger. A movement records its bin and lot. Open purchase orders still keep `incoming` on the stock level.

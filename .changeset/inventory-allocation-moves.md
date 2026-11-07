---
"better-supabase": minor
---

The inventory block gets the SQL functions `release_allocation(allocation)`, which releases one open allocation, and `transfer_allocation(allocation, document_type, document_id, line_id)`, which moves an open allocation to another document. They replace the app SQL that updated `stock_allocations` rows. Run `better-supabase upgrade` and generate a migration with `supabase db schema declarative sync`.

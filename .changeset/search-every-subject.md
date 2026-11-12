---
"better-supabase": minor
---

The search block indexes more record types. The quotes, invoices, orders, requests for quotation, tills, bookings, assets, leases, expenses, shipments, contracts, forms, documents, incidents, care plans, laboratory, maintenance, dispatch and ledger modules now declare a `search` title on their main subject, so `search(q)` finds their records once you run `better-supabase upgrade` and apply the migration. The migration backfills the index with `search_reindex`.

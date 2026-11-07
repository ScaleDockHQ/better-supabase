---
"better-supabase": minor
---

The inventory client gets `releaseAllocation` and `transferAllocation`, and the SQL function `transfer_allocation` records the new `allocation.transferred` event, with the new document in `toDocumentType` and `toDocumentId`. Run `better-supabase upgrade` and generate a migration with `supabase db schema declarative sync`.

---
"better-supabase": patch
---

A member without `ledger.read` now reads the ledger transactions that moved an account they can read. The read policy compared each entry with itself instead of with the transaction, so those members saw no transactions at all.

---
"better-supabase": patch
---

The ledger read policy now correctly exposes a whole transaction to a member who can read one of its entries. It compared each entry with itself instead of with the transaction, so members without `ledger.read` read no transactions at all. They now read every transaction that moved an account they can read; the transaction's entries on other accounts stay hidden unless they can read those accounts too.

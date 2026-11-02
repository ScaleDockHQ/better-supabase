---
"better-supabase": minor
---

Two more block reads, each one SQL call that runs as the caller. `banking.reconciliationBoard`
returns an account's status, its latest transactions and the best invoice suggestion for each
unmatched one. `orders.board` returns the orders by status with counts, totals per currency and the
latest orders of each status. Both appear in the generated `blocks.reads`, the catalog and the
example's migration.

---
"better-supabase": minor
---

`finance.reconcile` and the new `banking.reconcile` run as one database call. The `reconcile_bank_account` function reads the account's unmatched transactions and matches each to its best open invoice in one transaction, listing the ones that fail. The TypeScript hooks of `banking.reviewQueue` and `banking.acceptBestMatch` no longer fire inside `finance.reconcile`; the composite's own hook does.

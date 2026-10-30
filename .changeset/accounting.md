---
"better-supabase": minor
---

Add the `accounting` block (`better-supabase/blocks/accounting`): double-entry books in money beside
the operational ledger. It has a chart of accounts with account roles, journals, fiscal years of
monthly periods, draft entries that post when they balance and are numbered per journal and year
(`SAL-2026-00001`), reversals, dimensions, exchange rates and tax codes, and the period and
year-end close into retained earnings. It also has the trial balance, profit and loss, balance
sheet and general ledger reports. The permissions are `accounting.read`, `accounting.write`,
`accounting.post`, `accounting.close` and `accounting.manage`. ADR 0136 explains the split from
`ledger`.

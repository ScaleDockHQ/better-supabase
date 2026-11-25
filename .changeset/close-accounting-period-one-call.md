---
"better-supabase": minor
---

`finance.closePeriod` and the new `accounting.closePeriodIfClear` run as one database call. The `close_accounting_period_if_clear` function checks the blockers and closes the period in one transaction, and a blocked period returns its blockers. The TypeScript hooks of `accounting.closeBlockers` and `accounting.closePeriod` no longer fire inside `finance.closePeriod`; the composite's own hook does.

---
"better-supabase": minor
---

The `accounting` block is now a general ledger. Accounts gain `normalSide`, `level`, roll-ups through
`parentId`, `defaultTaxCodeId` and `active`. Periods can be locked with `lockPeriod`, and posting
into one fails with `ACCOUNTING_PERIOD_LOCKED`. Journals gain a contra and a bank account, entry
lines gain `taxAmount`, and `cost_center` and `cost_object` are built-in dimensions. Opening balances
(`saveOpeningBalances`, `postOpeningBalances`) are carried forward by `closeFiscalYear`. New reports
are `columnBalance`, `journalListing` and `periodTrialBalance`, and billable time gains
`wipValuation`. The `imports` block gets the `accounting_account`, `accounting_journal`,
`accounting_entry` and `accounting_opening_balance` targets, which may post into closed periods but
never locked ones. The SQL functions `save_accounting_account` and `save_accounting_journal` take
extra arguments, so run `better-supabase upgrade` to regenerate the module.

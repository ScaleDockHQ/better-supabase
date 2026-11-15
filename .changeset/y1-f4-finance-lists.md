---
"better-supabase": minor
---

Pages the finance blocks by the block list contract (ADR 1077). `accounting`
gains `accountPage` and `entryPage`, `banking` gains `accountPage` and
`batchPage`, `billable-time` gains `ratePage` and `getRate`, `expenses` gains
`categoryPage`, `reportPage` and `expensePage`, `invoices` gains `page` and
`get`, and `scores` gains `modelPage`, each with facets and a count. Every list
takes `q`, sorts, array filters and a keyset cursor, and a `get` for an unknown
id returns a `not_found` error. The SQL adds `page_accounting_accounts`,
`page_accounting_entries`, `page_bank_accounts`, `page_payment_batches`,
`page_time_rates`, `get_time_rate`, `page_expense_categories`,
`page_expense_reports`, `page_expenses`, `page_invoices`, `get_invoice` and
`page_score_models`, and the generated schema files need `better-supabase
upgrade`. The array methods keep working and are deprecated. `billing` and
`catalog` have no list function to page, so they are unchanged.

| Old                      | New                      |
| ------------------------ | ------------------------ |
| `accounting.accounts`    | `accounting.accountPage` |
| `accounting.entries`     | `accounting.entryPage`   |
| `banking.accounts`       | `banking.accountPage`    |
| `banking.paymentBatches` | `banking.batchPage`      |
| `billableTime.listRates` | `billableTime.ratePage`  |
| `expenses.categories`    | `expenses.categoryPage`  |
| `expenses.list`          | `expenses.reportPage`    |
| `expenses.listExpenses`  | `expenses.expensePage`   |
| `invoices.list`          | `invoices.page`          |
| `scores.models`          | `scores.modelPage`       |

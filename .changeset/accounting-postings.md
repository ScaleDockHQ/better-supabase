---
"better-supabase": minor
---

The `accounting` block now books other blocks' documents in the same transaction. Invoices book on
issue, payment, refund and void. Expense reports book on approval and reimbursement. Costed stock
movements book at average cost, lease rent charges and payments book as they post, and gifts book
when they post and reverse on refund. Entries post at once, or stay drafts with the new `autoPost:
false` option. `postSource(sourceType, sourceId)` books a document by hand. Blocks declare their
sources through the new `accounting` contribution kind. The generic chart maps a new `expense`
role.

`taxReport(organizationId, since, until)` sums posted tax per tax code and report box, with
`salesTax`, `purchaseTax` and `netTax`. The `TaxReportFormat` port (`apiVersion: 1`, checked with
`taxReportFormatOf`) renders a report as a country's file, and none is bundled. Budgets
(`saveBudget`, `budget`, `budgets`) hold amounts per account, period and dimensions, and
`budgetVsActual` compares them with the posted amounts. Saving a budget records
`accounting_budget.created` or `accounting_budget.updated`. Apply the new migration with
`better-supabase upgrade`.

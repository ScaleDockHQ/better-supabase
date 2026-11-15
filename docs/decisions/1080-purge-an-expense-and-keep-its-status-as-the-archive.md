# 1080: Purge an expense and keep its status as the archive (lane Y2)

- Status: accepted
- Date: 2026-11-15
- Amends: 1041

## Context

ADR 1041 puts expenses in its first group. The standalone expense has a
status (`draft`, `submitted`, `approved`, `rejected`, `reimbursed`) and
`delete_expense` removes a draft, or with `permissions.deleteSubmitted` a
submitted or approved one. The report path (`expense_reports` with lines) has
no delete: a report is cancelled, and a line is removed while the report is a
draft. A rejected or reimbursed expense is the record of what an employee
claimed and what the company paid, so it belongs in the ledger and exports.

## Decision

`expenses` adds no column and no `archive` or `restore`. The terminal statuses
already say that an expense is closed, `list_expenses` filters by `status`, and
hiding a reimbursed expense from its owner's list would break a payroll
reconciliation. `delete_expense` becomes `purge_expense` and records
`expense.purged`. Its key is `permissions.purge`, then the former
`permissions.delete`, then `expenses.manage`; `deleteSubmitted` keeps its name
and meaning. The report path is unchanged because it has no hard delete.

## Consequences

Breaking: `expenses.deleteExpense`, `delete_expense` and `expense.deleted`. The
`delete` permission key is still read when `purge` is unset, so existing
configs keep working. The 0.66 to 0.67 guide has the old-to-new table.

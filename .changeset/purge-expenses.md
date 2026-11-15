---
"better-supabase": minor
---

Breaking: an expense's hard delete is `purge`, behind `permissions.purge`, which
falls back to the former `delete` key and then `expenses.manage` (ADR 1082). A
rejected or reimbursed expense keeps its status as the archive, so expenses get
no `archive`, `restore` or new column.

| Before                       | After                                     |
| ---------------------------- | ----------------------------------------- |
| `expenses.deleteExpense(id)` | `expenses.purgeExpense(id)`               |
| `delete_expense(id)` (SQL)   | `purge_expense(id)`                       |
| event `expense.deleted`      | event `expense.purged`                    |
| `permissions.delete`         | `permissions.purge` (`delete` still read) |

Run `better-supabase upgrade` and apply the migration. See the 0.66 to 0.67
guide.

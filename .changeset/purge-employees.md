---
"better-supabase": minor
---

Breaking: an employee's hard delete is `purge`, behind `permissions.purge`, which
falls back to the write key (ADR 1079). Offboarding stays the archive, so
employees get no `archive`, `restore` or new column.

| Before                                                  | After                                           |
| ------------------------------------------------------- | ----------------------------------------------- |
| `employees.delete(id)`                                  | `employees.purge(id)`                           |
| `delete_employee(id)` (SQL)                             | `purge_employee(id)`                            |
| event `employee.deleted`                                | event `employee.purged`                         |
| hooks `before_employee_delete`, `after_employee_delete` | `before_employee_purge`, `after_employee_purge` |

Run `better-supabase upgrade` and apply the migration. See the 0.66 to 0.67
guide.

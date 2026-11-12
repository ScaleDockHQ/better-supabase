---
"better-supabase": minor
---

The `employees` block has a record binding. `employeeContractsBinding` loads an employee's contracts on the employee's page, reads again on `employee.updated` and `employee.deleted`, and has a `remove` write that needs `options.contracts: "editable"`. `better-supabase/blocks/employees` exports it, and `employeesBlock.record` is set.

| Before                                      | After                                                 |
| ------------------------------------------- | ----------------------------------------------------- |
| `employeesBlock.record` is `undefined`      | `employeesBlock.record` is `employeeContractsBinding` |
| Contracts loaded by hand on the detail page | `bsb.record("employee", id)` includes the contracts   |

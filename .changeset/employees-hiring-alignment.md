---
"better-supabase": minor
---

Employees and hiring take the options an HR app needs for safe edits and its own application columns.

- Employees: `options.contractOverlap: "deny"` keeps the previous contract as it is and fails `addContract` and `updateContract` with `EMPLOYEE_CONTRACT_OVERLAP` when the dates overlap another contract.
- Employees: `update(changes, { atomic: true })` applies a batch as one unit, and a change with `expectedUpdatedAt` fails with `EMPLOYEE_STALE` when the employee changed since. Employees now return `updatedAt`.
- Employees: `delete(employeeId)` (`delete_employee` in SQL) removes an employee created by mistake, moves the reports, records `employee.deleted` and fails with `EMPLOYEE_IN_USE` while other rows point at it. It runs the `before_employee_delete` and `after_employee_delete` hooks.
- Employees: `options.offboarding: { reports: "keep" }` leaves the reports with an offboarded employee instead of moving them to the manager.
- Hiring: `options.applicationExtraColumns` adds columns to the applications table. `apply` writes them from `fields`, and applications return them under `fields`.

# 1079: Purge an employee and keep offboarding as the archive (lane Y2)

- Status: accepted
- Date: 2026-11-15
- Amends: 1041

## Context

ADR 1041 puts employees in its first group. An employee already has an
archive: `offboard_employee` sets the status `offboarded`, the end date and
the reason, moves the reports and records `employee.offboarded`. An offboarded
employee leaves the org chart and `reports_of`, and `update_employees` refuses
to move a status back from `offboarded`. Only `delete_employee`, meant for a
record created by mistake, was a hard delete.

## Decision

`employees` adds no column and no `archive` or `restore`. A second way to
hide an employee would disagree with the status, and a restore would have to
reopen an employment (a rehire), which is a new employee with a new start date
and contract. `delete_employee` becomes `purge_employee` and records
`employee.purged`. It needs `permissions.purge`, falling back to the write key
the delete used, and keeps the report handling and the `EMPLOYEE_IN_USE`
refusal. The hooks `before_employee_delete` and `after_employee_delete` become
`before_employee_purge` and `after_employee_purge`.

Read paths need no change: lists, the org chart and exports already take the
status into account, and `get_employee` keeps returning an offboarded
employee.

## Consequences

Breaking: `employees.delete`, `delete_employee`, `employee.deleted` and the two
delete hooks. The 0.66 to 0.67 guide has the old-to-new table.

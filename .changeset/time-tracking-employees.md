---
"better-supabase": minor
---

`time-tracking` takes `on.<type>.column` over your own entries table: a record type keeps its id in its own foreign key column (cast to the record's `idType`), and `subject_type` and `subject_id` can be mapped to `null` once every type has one. `options.owner: "employee"` (with `approvals: false` and the employees block) keeps entries and timesheets per employee, so an employee without an account has timesheets: the timesheet key is the employee and the week, `columns.timesheets.user` can be `null`, `log_time`, `list_time_entries`, `get_timesheet`, `submit_timesheet` and `list_timesheets` take an `employee_id`, own entries and weeks are those of the caller's employee record, and rows and events carry `employeeId`. The client takes `employeeId` on `log`, `list`, `timesheet`, `submit` and `timesheets`. Without these settings the module renders as before.

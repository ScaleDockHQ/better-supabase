---
"better-supabase": minor
---

The `employees` SQL module and `better-supabase/blocks/employees` add the people an organization employs, with or without an account. An employee has a manager, team, job title, employment type, start and end date, and a status of preboarding, active, on leave or offboarded; the database refuses a manager who reports to the employee. `update` applies batched cell edits, `orgChart` and `reportsOf` read the tree (managers read their own reports), and `offboard` sets the end date and moves the reports up. `fromApplication` makes one employee from a hired application of the hiring block. Private details and a contract history with salaries in minor units sit behind `employees.view_sensitive`, declared to `data-lifecycle` for exports and anonymize rules. `employeesSubjects()` registers employees in `config.subjects`.

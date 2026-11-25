---
"better-supabase": patch
---

`create_employee` and `update_employees` refuse to set or change an employee's `userId` unless the caller also holds the employees block's `readSensitive` and `contractsRead` keys (`EMPLOYEE_LINK_FORBIDDEN`). Before, `employees.write` alone could link a colleague's record to the caller's own account and open that colleague's private details and contracts. Run `better-supabase upgrade` to regenerate the employees module.

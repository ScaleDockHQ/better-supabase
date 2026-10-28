---
"better-supabase": minor
---

Leave, expenses and the drive run over more of an app's own tables.

- Leave: `options.owner: "employee"` keys requests and balances by an employee of the employees block, so an employee without an account has leave too. The client takes `employeeId` on `request`, `list`, `balances`, `ledger` and `adjust`, and `employeeIds` on `accrue`. Reads return `employeeId`, and `userId` is now optional on requests, balances, ledger entries and feed entries.
- Leave: mapped `columns.requests.startPart` and `endPart` book half a day at either end of a request (`startPart` and `endPart` on `request`), combined with hours for an hours type, and overlaps are checked by half day.
- Leave: `tables.balances` maps the app's table of signed amounts (with an optional `expiresOn`) instead of the ledger block. The block sums it, adds taken and adjustment rows, and deletes the taken row when approved leave is cancelled. `adjust` takes `expiresOn`.
- Expenses: mapping `tables.reports` and `tables.lines` to `null` keeps each expense as one row of `tables.expenses`, without the approvals block or the ledger. The client adds `createExpense`, `updateExpense`, `submitExpense`, `decideExpense`, `reimburseExpense`, `getExpense` and `listExpenses`, and `options.owner: "employee"` keys expenses by employee. Report mode is unchanged.
- Drive: node kind and source, node and drive grant roles, drive kind, and connection provider and status may be enums in the app's tables.
- `add --adopt` and `apply --adopt` render the proposal with the authorization provider, so calendar `accessFunctions` in the `{ rows, key }` form and drive `roleFunctions` in the `{ rows, roles }` form no longer fail with the `rowsWith` error.

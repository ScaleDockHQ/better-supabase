---
"better-supabase": minor
---

Adopter gaps, round 42: approval requests under the app's own policy and for a named requester, floors for dotted actions and every subject type, switchable and enriched approval notifications, extra columns on tenant policies, approvals for leave by employee, per-employee timesheets and expenses without reports, and actors and reasons on the invoice status changes the block writes.

- Approvals: the service role passes `policy` (steps, mode, self-approval, expiry, `managerOf`) to `request`, which only tightens the floor and the matching tenant and platform policies, or stands alone where none matches. `requestedBy` names the user it files for, who then can't approve the request. A signed-in caller passing either fails with `APPROVAL_FORBIDDEN`. In SQL, `request_approval` takes trailing `policy` and `requested_by` arguments, and `open_approval` takes `requested_by`.
- Approvals: floor action names take dotted segments (`quote.send`), and a floor under subject type `"*"` covers an action for every subject type.
- Approvals: `options.notifications: false` turns the block's approval notifications off; an `approval_notification(request_id, kind, notification)` hook adds to a notification or skips it.
- Approvals: `options.policyExtraColumns` adds columns to `approval_policies`, written from `savePolicy({ fields })` and returned under `fields`.
- Approvals: a policy's `managerOf` points a manager step at an employee's manager instead of the requester's.
- Leave: `options.approvalOwner: "employee"` makes the request's employee the approval's requester and their manager the manager step.
- Time tracking: `owner: "employee"` no longer needs `approvals: false`; each submitted week files a request with the approvals block, whose decision sets the week's status.
- Expenses: `options.standaloneApprovals` (without reports) files each submitted expense with the approvals block under `options.policy`, whose decision approves or rejects it.
- Invoices: `void`, `writeOff`, `reversePayment`, `charge` and `removeCharge` take an `actor`, and the void, write-off and reversal reasons go to the state machine's history, so a machine over invoices can write its own history. Their SQL functions take a trailing `actor jsonb`.

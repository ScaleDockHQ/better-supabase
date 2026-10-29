---
"better-supabase": minor
---

Approval steps with `required: "all"` wait for each named approver, and managers can decide leave and expenses directly. Run `better-supabase upgrade` and generate a migration.

- Approvals: a `required: "all"` step completes only once each listed user, or a delegate acting for that user, has approved. Before, any approvals reaching the count completed it, so a delegate and the user who delegated counted twice. After the step escalates, the fallback approvers count toward the number again. Steps resolved from `"all"` keep `all: true` in the policy snapshot and in `listPolicies`; a tenant can't set it on other steps.
- Leave and expenses: `options.approver: "manager"` lets the requester's manager from the employees block call `decide_leave_request`, `decide_expense` and `decide_expense_report` (`decide`, `decideExpense` and `decideExpenseReport`), next to holders of the approve permission. The default stays `"permission"`.
- Leave: with `approvals: false` on the block's own tables, request reads no longer refer to the approval column, which the table doesn't have without the approvals block.
- Time tracking: with `approvals: false`, `approve(id, { decidedBy })` and `reject(id, note, { decidedBy })` let the service role record the user who decided (`decided_by` in SQL), never the week's owner.

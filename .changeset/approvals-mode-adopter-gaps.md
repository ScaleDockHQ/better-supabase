---
"better-supabase": minor
---

Leave in approvals mode stamps the approval's decision on the request (`rejected_at`, `decided_by`, `decision_note`, and `cancelled_at` when the approval is cancelled) as `decide_leave_request` does, and `options.approvalSubject` names the subject type its approvals are filed under. The approvals block takes `options.requestColumns`, which fills your own columns of requests a block files and wins over a caller's `fields`. Expenses with `standaloneApprovals` take `selfDecideWhenTopOfChain`. Time entries take `approvalRequired`, an app function that can skip the approval of a week, and `selfApproveWhenTopOfChain`, which approves a week at once when its owner is the only one who could decide it. The organizations client gets `soleOwnedOrganizations`. Banking takes `options.primary: "organization"` for one primary account per organization and `options.optionalCurrency` for accounts without a currency.

Behaviour changes to check:

- `sole_owned_organizations(member)` no longer raises when a caller asks about another member. It returns the organizations where the caller may remove members, so an empty list means "no right to ask, or not a sole owner there", never "safe to remove".
- `cancel_approval` on a leave request's approval now cancels the leave request too (`cancelled_at`, `cancelled_by`, `leave_request.cancelled`).
- Leave in approvals mode records `leave_request.rejected` on a rejection, and its requests table gets the nullable `rejected_at`, `decided_by` and `decision_note` columns.
- `request_approval` refuses the subject types leave, expenses and time entries file themselves (`leave_request` or `approvalSubject`, `expense`, `timesheet`) for anyone but the service role, with `APPROVAL_SUBJECT_BLOCK_FILED`, and those blocks act only on the approval their own row points at.

---
"better-supabase": minor
---

Leave, expenses and timesheets filed for an employee without an account no longer make the member who filed them the approval's requester, so that member can decide them. A mapped `rejected_at` keeps a leave request rejected in approvals mode without an approval request, so `update` and `cancel` fail with `LEAVE_REQUEST_CLOSED`. Time entries take `options.writer`, an app function `(tenant, owner uuid) returns boolean` that lets more callers log, change and archive another owner's entries and submit and withdraw their weeks. `sole_owned_organizations` for another member now fails with `ORGANIZATION_FORBIDDEN` when the caller lacks the remove permission, instead of returning an empty or partial list.

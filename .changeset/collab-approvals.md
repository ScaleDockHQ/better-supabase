---
"better-supabase": minor
---

Add the `approvals` block (`better-supabase/blocks/approvals` and the `approvals` SQL module): approval requests with steps per subject type and action, approvers by permission, role, team or user, a required count, delegation, self-approval off by default, expiry and reminders. The final approval runs a state-machine transition or enqueues a job, approvers and requesters are notified through the notifications module, and the module records `approval.*` events. State machines gain `requiresApproval`, which reserves transitions for an approved request (`STATE_APPROVAL_REQUIRED`).

---
"better-supabase": minor
---

Approval requests gain a `consumed` status. `consume_approval` (`consume()` in TypeScript) now sets the status to `consumed` as well as `consumed_at`, `ApprovalStatus` includes `consumed`, and a check keeps `consumed_at` set exactly when the status is `consumed`. `is_approved` still answers true for a consumed request.

The approvals module moves to version 6. `better-supabase upgrade` writes a reviewed migration that allows the new status, moves requests consumed before (with `consumed_at` set and status `approved`) to `consumed`, and adds the check. Over a requests table of your own, `consume` keeps setting only `consumed_at` and leaves the status alone, so the app's status check or enum keeps working.

Code with an exhaustive map over `ApprovalStatus`, such as a `Record<ApprovalStatus, string>` of labels, needs an entry for `consumed`.

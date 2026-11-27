---
"better-supabase": minor
---

The approvals block's `approval_eligible_ids_in` no longer runs the approver hooks once per pending request. A block's `decides` rule runs once per subject type through the new `options.deciderMany` of leave, expenses and time entries, the set form of `options.decider`. The provider's `isApprover` runs once per distinct kind, tenant, requester and approvers, and only for requests nothing else lets the caller decide, or once in all through the new `authorization.functions.isApproverMany` template. Approvals module version 8.

---
"better-supabase": patch
---

Approvals: the authorization provider's `isApprover` template can use `{approvers}`, and a manager step reads the employees block's status mapping.

- `authorization.functions.isApprover` takes `{approvers}`, a `jsonb` value with the approvers the request waits on now. `approval_eligible` passes the current step's `approvers` with its `required` count, or the step's `escalateTo` while the step is escalated, for example `{"users": ["<uuid>"], "manager": true, "required": 1}`. AI tool calls and support sessions pass `null`. A provider that keeps covers uses it to let an out-of-office cover decide for the approvers a policy names.
- A `manager: true` step no longer lets a manager decide whose employee row holds the app's mapped `offboarded` value (`values.employees.status`); it compared against the literal `offboarded` before.

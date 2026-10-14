---
"better-supabase": minor
---

`approval_eligible` also asks the provider's `isApprover` for the kind `<type>.<action>`, and never for the requester. `createApprovals` takes `approverOf`, `wakeOnApproval` from `better-supabase/workflow-sdk` resumes a run waiting on a request id when the request is approved, rejected, expired or cancelled, and a workflow-builder approval node can file an approvals request and wait on its id.

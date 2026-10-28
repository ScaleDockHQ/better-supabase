---
"better-supabase": minor
---

Approvals: tenant policies, confirm or authorize modes, manager approvers and single-use approvals.

- `blocks.approvals.options.tenantPolicies: true` adds an `approval_policies` table per organization. A tenant policy tightens the configured policy for the same subject type and action: its steps run after the configured ones, the stricter mode wins, `selfApproval` holds only when every policy allows it and the shortest expiry wins. `conditions` is a rules filter tree over the subject type's rule fields, matched against the request payload (needs the automations block). The client adds `listPolicies`, `savePolicy` and `removePolicy`, and the module records `approval_policy.saved` and `approval_policy.removed`.
- A configured policy with `steps: []` asks for nothing until a tenant policy adds a step or a mode; it needs `tenantPolicies`.
- A policy's `mode` is `"authorize"` (the default) or `"confirm"`, where the requester may approve their own request and that approval finishes it. Requests return `mode`.
- `steps[].approvers.manager: true` lets the requester's manager from the employees block decide the step.
- `requirement(subjectType, action, payload)` returns what a request would need, or `null` when nothing is required; `request` then fails with `APPROVAL_NOT_REQUIRED`.
- `request(subject, { fingerprint })` binds the approval to an operation, and `consume(id, fingerprint)` uses an approved request once (`APPROVAL_CONSUMED`, `APPROVAL_NOT_APPROVED`, `APPROVAL_FINGERPRINT_MISMATCH`), recording `approval.consumed`. `approvalFingerprint(value)` builds the fingerprint as the SHA-256 of sorted-key JSON. Requests return `fingerprint` and `consumedAt`.
- The SQL `request_approval` takes a trailing `fingerprint` argument, so calls with positional arguments keep working. In managed mode, run `better-supabase upgrade` and generate a migration to add the `fingerprint` and `consumed_at` columns; over your own table, map `fingerprint` and `consumedAt` to use fingerprints and `consume`.

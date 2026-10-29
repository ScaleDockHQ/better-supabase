---
"better-supabase": minor
---

Adopter gaps, round 41: approval policies by effect, catch-all and platform rows, payload conditions, tenantless requests, every holder of a permission, escalation and service-role deciders; quote working copies, version lines, fixed and pay-first deposits, subscription periods, withdrawals and app portal answers; and actors on block-written status changes.

- Approvals: floors take `effects` and an `"*"` action; tenant policies match `subjectType: "*"`, `action: "*"` and an `effect`. `options.platformPolicies` keeps runtime-edited platform policies (no organization) that apply everywhere and stand in for a missing floor. `options.conditions: "payload"` matches conditions against the request payload without automations.
- Approvals: `options.tenantless` lists subject types whose requests may have no organization (`request(..., { tenantless: true })`); `organizationId` is `null` on them.
- Approvals: `required: "all"` with only `approvers.permission` asks every holder; `escalateAfter` and `escalateTo` with `escalate_approvals()` let fallback approvers decide a step that waited; `approve` and `reject` take `{ decidedBy }` for the service role.
- Leave and expenses: `decide` and `decideExpense` take `decidedBy`, which the service role passes so the decider is kept.
- Quotes: `options.workingCopy` edits sent quotes while the customer sees the last published version (`publish` on the same link); `options.versionLines` keeps published lines as rows with ids in `quote_version_lines`, and `selected` takes those ids. `depositAmount`, `depositRequired`, line `periods`, `withdraw`, `decide` with an `actor`, and `portalView` for the service role.
- State machine: `actor.id` names the user the service role acts for; quotes (`send`, `publish`, `revise`, `withdraw`, `decide`, customer answers) and invoices (`issue`, `recordPayment`) pass their actor to the history.
- Invoices: `fromQuote` copies a subscription line as quantity times periods.

Configs that set none of the new options behave as before. `ApprovalRequest.organizationId` and `ApprovalTenantPolicy.organizationId` are typed `string | null`.

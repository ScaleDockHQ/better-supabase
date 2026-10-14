---
"better-supabase": minor
---

Support sessions now deny by default. `supportSessions` refuses every start unless `authorize` or the `support.authorize` authorization hook allows it, and `authorize: "store"` leaves the decision to the store. A start also needs a second admin by default (`policy.approval: "distinct"` and the `support-sessions` module option `approval: "distinct"`): the admin calls `support.request`, a different admin calls `support.approve`, and the SQL module refuses self-approval in `approve_support_request` and in a check constraint on the new `support_requests` table. Set both options to `"none"` to keep the old behaviour.

`approverOf` and the SQL `isApprover` template decide who may approve, with kind `support-session` for support requests and kind `ai-tool` (subject the tool's name) for `decide_ai_tool_approval`, where `isApprover` always refuses the approval's owner. The ai-chat module still reads `canApprove` when `isApprover` is unset.

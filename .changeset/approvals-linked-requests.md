---
"better-supabase": minor
---

With the `approvals` SQL module installed, AI-chat tool calls that wait for approval (`ai_tool_approval`, action `run`) and support access requests for a tenant (`support_request`, action `start`) also file an approval request. Deciding either side decides the other: `decide_approval` approves or denies the tool call and approves or closes the support request, and `decide_ai_tool_approval` or `approve_support_request` settles the approval request. The owning module still decides who may approve, these requests can't be delegated, and `approvals.read` alone doesn't list them, so tool inputs and support reasons stay with their approvers.

---
"better-supabase": patch
---

The approvals module (version 4) reads the caller's role, team and manager approvals once per
statement through the new `approval_fact`, kept with `memo_get` and `memo_set` under the statement
start and a generation that statement triggers on memberships, the roles table, team members and
employees move. Permission approvers still call `can()` for each request, so any authorization
provider decides them live. The request's status, step and decisions stay live per row.
`approval_eligible` gains an `approval_eligible(approval_requests)` overload, so
`approval_eligible_ids`, `my_work` and app policies pass the row instead of fetching it again. Run
`better-supabase upgrade`, then `add --adopt` for the block row.
